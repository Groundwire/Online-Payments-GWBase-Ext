global virtual with sharing class PaymentToSalesforceGW extends gwop.PaymentToSalesforce {
/*-----------------------------------------------------------------------------------------------
* Written by Evan Callahan, copyright (c) 2010 Groundwire
* This program is released under the GNU Affero General Public License, Version 3. http://www.gnu.org/licenses/
* 
* This class processes an online payment, creating an opportunity record. You can call it from 
* web pages or VF pages that take payments, or from a payment notification listener.  
*
* This interface is an attempt to support multiple payment processors in a generic way.  You may
* want to override the methods in this class, but try not to add any processing that is specific
* to a single payment processing application.
*
* Recurring payments are supported; we create a Recurring Payment object to store the metadata
* about the payment, such as frequency, then create one related opportunity for each year's worth
* of payments. Individual payments result in payment installment child records.
* 
* TO DO:
*  support multiple items to products
*  compare to authnet and google payments to ensure future compatibility
*  [check on edge cases for setting values back into properties or not using them - e.g. setOppValues]
*  [check on whether unchanged contacts/accounts are getting updated]
-----------------------------------------------------------------------------------------------*/   

    // custom settings are retrieved in the constructor
    global gwop__OnlinePaymentSettings__c opSettings;

    public string INDIVIDUAL_ACCOUNT_NAME;
        
    // if a recurring payment record gets created or updated, we store it here
    public GWBase__recurring_payment_profile__c recurringPayment { get; private set; }

    // if a single installment payment gets created or updated, we store it here
    public GWBase__oppPayment__c installment { get; private set; }

    // for a new pledge, our implementation creates a list of future installments
    // with a defined number of occurences, and passes them back using this property
    public list<GWBase__oppPayment__c> futureInstallments { get; private set; }
    
    // for refunds, we update the old payment and also create a new one
    public GWBase__oppPayment__c refundInstallment { get; private set; }

    //opportunity to hold a new pledge with a defined total amount anc number of payments
    public opportunity pledgeOpp;
    
    // these store the set of fields to overwrite if provided
    public set<string> contactOverwrite; // = new set<string>();
    public set<string> accountOverwrite; // = new set<string>();

    // need fiscal year start month to be public for tests
    public integer fysm;

    // these objects store the "old" version of the payerAccount and payerContact
    // if they are null, it indicates a new payer (or none at all)
    public static account oldAccount;
    public static contact oldContact;
    public static boolean payerDataSaved;
    
    // when creating an installment list, this allows us to save the start date for the following year
    //static date firstPaymentNextYear;

    // method called when class is dynamically created by ClassFactory, when
    // constructor and static initialization won't be done.
    global virtual override void initialize() {
        
        INDIVIDUAL_ACCOUNT_NAME = GWBase.ONEN_Constants.INDIVIDUAL_ACCOUNT_NAME;
        contactOverwrite = new set<string>();
        accountOverwrite = new set<string>();
        
        //itemList = new list<gwop.OnlinePayment.Item>();
        
        // get settings - there are defaults for most of them if it isn't set
        opSettings = gwop__OnlinePaymentSettings__c.getInstance();
        if (opSettings == null || Test.isRunningTest()) opSettings = defaultSettings();

        // get the set of fields we will overwrite
        if (opSettings.gwop__CONTACT_FIELDS_TO_OVERWRITE__c != null)
            contactOverwrite.addAll(opSettings.gwop__CONTACT_FIELDS_TO_OVERWRITE__c.split(';'));
        if (opSettings.gwop__ACCOUNT_FIELDS_TO_OVERWRITE__c != null)
            accountOverwrite.addAll(opSettings.gwop__ACCOUNT_FIELDS_TO_OVERWRITE__c.split(';'));        
    }

    // constructor
    global PaymentToSalesforceGW() {
        initialize();
    }

    // method to initialize settings when they don't exist, or in tests
    global static gwop__OnlinePaymentSettings__c defaultSettings() {
        gwop__OnlinePaymentSettings__c ops = new gwop__OnlinePaymentSettings__c();
        ops.gwop__Opp_Stage_for_New_Payments__c = GWBase.ONEN_Constants.OPP_DEFAULT_WON_NOT_THANKED_STAGE;
        ops.gwop__Opp_Stage_for_Pending_Payments__c = 'Payment Pending';
        ops.gwop__Opp_Stage_for_Lost_Opps__c = GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_LOST_STAGE;
        ops.gwop__Opp_Stage_for_Closed_Opps__c = GWBase.ONEN_Constants.OPP_DEFAULT_WON_NOT_THANKED_STAGE;
        ops.gwop__Opp_Stage_for_Refunds__c = GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_LOST_STAGE;
        ops.gwop__Opp_Stage_for_Partial_Refunds__c = GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_WON_STAGE;
        ops.gwop__Match_Email_Only_When_Name_Matches__c = true;
        ops.gwop__Home_Address_is_Other__c = true;
        ops.gwop__Default_Record_Type__c = GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_CONTACT;
        ops.gwop__Create_Pending_Opps__c = true;
        ops.gwop__Create_Lost_Opps__c = false;
        ops.gwop__Contact_Fields_to_Overwrite__c = 'address;phone';
        ops.gwop__Company_Name_Indicates_Org_Payer__c = false;
        ops.gwop__Dont_Match_Contacts_by_Email__c = false;
        return ops;
    }

    /*------------------------------------------------------------------------------------
    * fsetPayer method
    * tries to match payer data to an existing account or contact
    * if it does not find a match, it creates a new contact (and/or account) for the opp
    * returns true if there is a designated payer one way or another, false for failure
    -------------------------------------------------------------------------------------*/ 
    public boolean fsetPayer() {
        setPayer();
        return true;
    }
    
    global virtual override void setPayer() {
        //system.debug('fsetPayer method');
        //system.debug(this);
        
        payerContact = null;
        payerAccount = null;
        paymentOpp = null;
        payerMatchResult = null;
        
        //system.debug('entering fsetPayer with recurringTxnId: ' + payment.recurringTxnId + ' and txnId: ' + payment.txnId);
        // first look for an existing recurring payment with the specified transaction Id, 
        // and set the acct/con ids based on that
        if (payment.recurringTxnId != null) {
            GWBase__recurring_payment_profile__c[] rp = [Select GWBase__Type__c, GWBase__Transaction_Id__c, GWBase__Payment_Period__c, GWBase__account__c,  
                Name, GWBase__Frequency__c, GWBase__End_Date__c, GWBase__Contact__c, GWBase__Amount__c, GWBase__account__r.name, GWBase__account__r.BillingCity, 
                GWBase__account__r.BillingStreet, GWBase__account__r.billingCountry, GWBase__account__r.BillingPostalCode, 
                GWBase__account__r.billingstate, GWBase__account__r.phone, GWBase__account__r.gwop__online_payer_id__c,
                GWBase__contact__r.firstname, GWBase__contact__r.lastname, GWBase__contact__r.email, GWBase__contact__r.gwop__Online_Payer_Id__c,   
                GWBase__contact__r.MailingCity, GWBase__contact__r.MailingStreet, GWBase__contact__r.MailingCountry, GWBase__contact__r.GWBase__householdName__c,
                GWBase__contact__r.MailingPostalCode, GWBase__contact__r.Mailingstate, GWBase__contact__r.OtherCity, GWBase__contact__r.OtherStreet, 
                GWBase__contact__r.OtherCountry, GWBase__contact__r.OtherPostalCode, GWBase__contact__r.Otherstate, GWBase__contact__r.phone, 
                GWBase__contact__r.GWBase__anonymous__c, GWBase__contact__r.homephone, GWBase__contact__r.fax
                From GWBase__recurring_payment_profile__c where GWBase__Transaction_Id__c = : payment.recurringTxnId and 
                (GWBase__end_date__c = null or GWBase__end_date__c >= THIS_MONTH) 
                order by createddate desc limit 1];
            if (!rp.isEmpty()) {
                recurringPayment = rp[0];
                if (recurringPayment.GWBase__account__c != null) {
                    accountId = recurringPayment.GWBase__account__c;
                    payerAccount = recurringPayment.GWBase__account__r;
                }
                if (recurringPayment.GWBase__contact__c != null) {
                    contactId = recurringPayment.GWBase__contact__c;
                    payerContact = recurringPayment.GWBase__contact__r;
                }
                // make sure pledgeOpp cleared, since we are dealing with recurring payments, not a pledge w/ installments.
                pledgeOpp = null;
            } else { 
                // make sure recurringPayment cleared, since we are dealing with a pledge, not a recurring payment.
                recurringPayment = null;
                
                //also look for opps, which represent pledges with a defined number of payments
                opportunity[] pledges = [select id, closedate, amount, GWBase__Total_Paid__c, recordtypeid, GWBase__recurring_payment_profile__c, 
                    isWon, accountid, account.name, account.BillingCity, GWBase__ContactId__c, type, stagename,
                    account.BillingStreet, account.billingCountry, account.BillingPostalCode, gwop__Online_Pledge_Transaction_Id__c,
                    account.billingstate, account.phone, account.gwop__online_payer_id__c from opportunity 
                    where gwop__Online_Pledge_Transaction_Id__c = : payment.recurringTxnId
                    order by createddate desc limit 1];
                if (!pledges.isEmpty()) { 
                    // set the opp and account to what we found
                    pledgeOpp = pledges[0];
                    accountId = pledges[0].accountId;
                    payerAccount = pledges[0].account;  
                    contactId = pledges[0].GWBase__ContactId__c;
                    
                }
            }
        }
        // look for opp with specified transaction id and set the acct/con ids based on that
        if (payment.txnId != null) {
            opportunity[] opp = [select id, closedate, recordtypeid, GWBase__recurring_payment_profile__c,  
                isWon, accountid, account.name, account.BillingCity, GWBase__ContactId__c, type, stagename,
                account.BillingStreet, account.billingCountry, account.BillingPostalCode, amount,
                account.billingstate, account.phone, account.gwop__online_payer_id__c from opportunity 
                where gwop__Online_Transaction_Id__c = : payment.txnId 
                order by createddate desc limit 1];
            if (!opp.isEmpty()) {
                // set the opp and account to what we found, only if we don't already have an opp for a pledge
                paymentOpp = opp[0];
                accountId = paymentOpp.accountId;
                payerAccount = paymentOpp.account;
                contactId = paymentOpp.GWBase__ContactId__c;
            } else if (payment.pmtStatus != gwop.OnlinePayment.PaymentStatus.REVERSED) {
                // also check for existing installment payment with this transaction Id
                GWBase__oppPayment__c[] opmt = [select id, GWBase__opportunity__c, GWBase__Online_Transaction_Id__c, GWBase__Amount__c, 
                	GWBase__isInstallment__c, GWBase__paid__c, GWBase__opportunity__r.accountid, GWBase__opportunity__r.amount,
                    GWBase__opportunity__r.closedate, GWBase__opportunity__r.recordtypeid, GWBase__opportunity__r.iswon, GWBase__opportunity__r.stagename,    
                    GWBase__opportunity__r.account.BillingCity, GWBase__opportunity__r.account.BillingStreet,
                    GWBase__opportunity__r.account.billingCountry, GWBase__opportunity__r.account.BillingPostalCode, 
                    GWBase__opportunity__r.account.billingstate, GWBase__opportunity__r.account.phone, 
                    GWBase__opportunity__r.account.name, GWBase__opportunity__r.account.gwop__online_payer_id__c,
                    GWBase__opportunity__r.GWBase__recurring_payment_profile__c, GWBase__opportunity__r.GWBase__ContactId__c // other fields?
                    from GWBase__oppPayment__c where GWBase__Online_Transaction_Id__c = : payment.txnId limit 1];
                if (!opmt.isEmpty()) {
                   	installment = opmt[0];
                    if (paymentOpp == null) {
                        paymentOpp = installment.GWBase__opportunity__r;
                        accountId = paymentOpp.accountId;
                        payerAccount = paymentOpp.account;
                        contactId = paymentOpp.GWBase__ContactId__c;
                    }
                }
            }
            if (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.REVERSED) {
	            // for refunds, look for the existing refund installment
                GWBase__oppPayment__c[] opmt = [select id, GWBase__opportunity__c, GWBase__Online_Transaction_Id__c, GWBase__Amount__c, 
                	GWBase__isInstallment__c, GWBase__paid__c, GWBase__opportunity__r.accountid, GWBase__opportunity__r.amount,
                    GWBase__opportunity__r.closedate, GWBase__opportunity__r.recordtypeid, GWBase__opportunity__r.iswon, GWBase__opportunity__r.stagename,    
                    GWBase__opportunity__r.account.BillingCity, GWBase__opportunity__r.account.BillingStreet,
                    GWBase__opportunity__r.account.billingCountry, GWBase__opportunity__r.account.BillingPostalCode, 
                    GWBase__opportunity__r.account.billingstate, GWBase__opportunity__r.account.phone,
                    GWBase__opportunity__r.account.name, GWBase__opportunity__r.account.gwop__online_payer_id__c,
                    GWBase__opportunity__r.GWBase__recurring_payment_profile__c, GWBase__opportunity__r.GWBase__ContactId__c // other fields?
                    from GWBase__oppPayment__c where GWBase__Online_Transaction_Id__c = : payment.txnId limit 1];
	
                if (!opmt.isEmpty()) {
                   	refundInstallment = opmt[0];
                    if (paymentOpp == null) {
                        paymentOpp = refundInstallment.GWBase__opportunity__r;
                        accountId = paymentOpp.accountId;
                        payerAccount = paymentOpp.account;
                        contactId = paymentOpp.GWBase__ContactId__c;
                    }
                }
            }
        }
        // for refunds, look for the previous payment we are refunding - might be a mirror payment
        if (installment == null && payment.parentTxnId != null) {
            GWBase__oppPayment__c[] opmt = [select id, GWBase__opportunity__c, GWBase__Online_Transaction_Id__c, GWBase__Amount__c,
            	GWBase__isInstallment__c, GWBase__paid__c, GWBase__opportunity__r.accountid, GWBase__opportunity__r.amount,
                GWBase__opportunity__r.closedate, GWBase__opportunity__r.recordtypeid, GWBase__opportunity__r.iswon, GWBase__opportunity__r.stagename,   
                GWBase__opportunity__r.account.BillingCity, GWBase__opportunity__r.account.BillingStreet,
                GWBase__opportunity__r.account.billingCountry, GWBase__opportunity__r.account.BillingPostalCode, 
                GWBase__opportunity__r.account.billingstate, GWBase__opportunity__r.account.phone,
                GWBase__opportunity__r.account.name, GWBase__opportunity__r.account.gwop__online_payer_id__c,
                GWBase__opportunity__r.GWBase__recurring_payment_profile__c, GWBase__opportunity__r.GWBase__ContactId__c // other fields?
                from GWBase__oppPayment__c where GWBase__Online_Transaction_Id__c = : payment.parentTxnId or 
                (GWBase__opportunity__r.gwop__Online_Transaction_Id__c = : payment.parentTxnId and GWBase__isInstallment__c = false)   
                limit 1];
            if (!opmt.isEmpty()) {
               	installment = opmt[0];
                if (paymentOpp == null) {
                    paymentOpp = installment.GWBase__opportunity__r;
                    accountId = paymentOpp.accountId;
                    payerAccount = paymentOpp.account;
                    contactId = paymentOpp.GWBase__ContactId__c;
                }
            }
        }
        
        // if we found an opp with an account, set company as payer
        if (paymentOpp != null && paymentOpp.AccountId != null && paymentOpp.Account.Name != INDIVIDUAL_ACCOUNT_NAME && paymentOpp.GWBase__ContactId__c == null) {
            //system.debug('fsetPayer assumes companyIsPayer: ' + paymentOpp.Account.Name);
            companyIsPayer = true;
        }        
        
        // if we found an opp, get the contact role for it
        if (paymentOpp != null && payerContact == null) {
            opportunityContactRole[] ocr = [select contactId, contact.firstname, contact.lastname, contact.email, 
                    contact.gwop__Online_Payer_Id__c,   contact.MailingCity, contact.MailingStreet, contact.MailingCountry, 
                    contact.MailingPostalCode, contact.Mailingstate, contact.OtherCity, contact.OtherStreet,  contact.GWBase__householdName__c,
                    contact.OtherCountry, contact.OtherPostalCode, contact.Otherstate, contact.phone, contact.GWBase__anonymous__c,
                    contact.homephone, contact.fax from opportunityContactRole  
                where opportunityId = : paymentOpp.id and isPrimary = true limit 1]; 
            if (!ocr.isEmpty()) {
                contactId = ocr[0].contactId;
                payerContact = ocr[0].contact;
            }
        }
        
        // if the contact or account id were prefilled, use them rather than looking for a match
        if (contactId != null) {
            contact[] c = [select id, firstname, lastname, email, gwop__Online_Payer_Id__c, GWBase__householdName__c,
                MailingCity, MailingStreet, MailingCountry, MailingPostalCode, Mailingstate,
                OtherCity, OtherStreet, OtherCountry, OtherPostalCode, Otherstate, GWBase__anonymous__c,
                phone, homephone, fax, accountid, account.name, account.BillingCity,
                account.BillingStreet, account.billingCountry, account.BillingPostalCode, 
                account.billingstate, account.phone, account.gwop__online_payer_id__c from contact
                where id = : contactId limit 1];
            if (!c.isEmpty()) payerContact = c[0];
        }
        if (payerContact == null && accountId != null) {
            account[] a = [select id, name, BillingCity, BillingStreet, billingCountry, BillingPostalCode, 
                    billingstate, phone, gwop__Online_Payer_Id__c from account
                where id = : accountId limit 1];
            if (!a.isEmpty()) payerAccount = a[0];
        }

        // set the match result property
        if (payerAccount != null || payerContact != null) {
            payerMatchResult = gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH;
            //system.debug('payerMatchResult: ' + payerMatchResult);
        }

        // next we try to match to a contact
        if (payerContact == null) {
        
            // look for the payer by email, secondary email, or payerId - an external ID from paypal or authnet
            //  if the setting indicates, skip the email match and only match on payerid
            contact idMatch;
            Contact[] cons;
            if (opSettings.gwop__Dont_Match_Contacts_by_Email__c == true) {
                cons = [select id, firstname, lastname, email, GWBase__secondary_email__c, gwop__Online_Payer_Id__c, GWBase__householdName__c,
                    MailingCity, MailingStreet, MailingCountry, MailingPostalCode, Mailingstate,
                    OtherCity, OtherStreet, OtherCountry, OtherPostalCode, Otherstate, GWBase__anonymous__c,
                    phone, homephone, fax, accountid, account.name, account.BillingCity,
                    account.BillingStreet, account.billingCountry, account.BillingPostalCode, 
                    account.billingstate, account.phone, account.gwop__online_payer_id__c from contact 
                    where ((gwop__Online_Payer_Id__c != null and 
                    (gwop__Online_Payer_Id__c = : payer.payerId or gwop__Online_Payer_Id__c = : payer.email)) 
                    )
                    order by lastModifiedDate limit 10 ];
            } else {
                cons = [select id, firstname, lastname, email, GWBase__secondary_email__c, gwop__Online_Payer_Id__c, GWBase__householdName__c,
                MailingCity, MailingStreet, MailingCountry, MailingPostalCode, Mailingstate,
                OtherCity, OtherStreet, OtherCountry, OtherPostalCode, Otherstate, GWBase__anonymous__c,
                phone, homephone, fax, accountid, account.name, account.BillingCity,
                account.BillingStreet, account.billingCountry, account.BillingPostalCode, 
                account.billingstate, account.phone, account.gwop__online_payer_id__c from contact 
                    where ((gwop__Online_Payer_Id__c != null and 
                    (gwop__Online_Payer_Id__c = : payer.payerId or gwop__Online_Payer_Id__c = : payer.email))
                    or (email != null and email = : payer.email)
                    or (GWBase__secondary_email__c != null and GWBase__secondary_email__c = : payer.email))
                    order by lastModifiedDate limit 10 ];
            }
                
            for (contact c : cons) {
                // if there is a payer Id match, that trumps other criteria
                if ((payer.payerId != null && payer.payerId == c.gwop__Online_Payer_Id__c) || 
                    (payer.email != null && payer.email == c.gwop__Online_Payer_Id__c)) {

                    payerContact = c;
                    break;
                }
                
                // if there is an email match, check last name/first letter of first name as well
                // replace previously found contact on any exact name match
                if (payer.email != null && 
                    (payer.email == c.email || payer.email == c.GWBase__secondary_email__c) &&
                    ((payer.lastName == c.lastName && payer.firstName == c.firstName) ||
                    (payerContact == null &&
                    (opSettings.gwop__MATCH_EMAIL_ONLY_WHEN_NAME_MATCHES__c == false ||
                    (payer.lastName == c.lastName && 
                        payer.firstName != null && payer.firstName != '' &&
                        c.firstName != null && c.firstName != '' &&
                        c.firstName.startsWith(payer.firstName.substring(0,1))))))) {

                    payerContact = c;
                }                   
            }
        }       

        // set the match result property
        if (payerMatchResult == null && payerContact != null) {
            payerMatchResult = gwop.OnlinePayment.MatchResult.CONTACT_MATCH;
            //system.debug('payerMatchResult: ' + payerMatchResult);
        }
    
        // look for a matching account if we do not already have a contact match 
        if (payerAccount == null && payer.companyName != null && payer.companyName != INDIVIDUAL_ACCOUNT_NAME &&
            (payerContact == null || companyIsPayer == true || opSettings.gwop__COMPANY_NAME_INDICATES_ORG_PAYER__c)) {
        
            // look for an account by payerId or account name
            for (account a : 
                [select id, name, BillingCity, BillingStreet, billingCountry, BillingPostalCode, 
                    billingstate, phone, gwop__Online_Payer_Id__c from account 
                    where ((gwop__Online_Payer_Id__c != null and 
                    (gwop__Online_Payer_Id__c = : payer.payerId  or gwop__Online_Payer_Id__c = : payer.email))
                    or name = : payer.companyName )
                    order by lastModifiedDate limit 10 ] ) {
                
                // if there is a payer Id match, that trumps other criteria
                if ((payer.payerId != null && payer.payerId == a.gwop__Online_Payer_Id__c) || 
                    (payer.email != null && payer.email == a.gwop__Online_Payer_Id__c)) {

                    payerAccount = a;
                    break;
                }
                
                // be sure to favor the right city
                if (payerAccount == null || a.billingCity == payer.billingAddress.city)
                    payerAccount = a;
            }
        }       

        // if there is a contact, we want that contact's account (if it isn't the default account)
        if (payerContact != null && payerContact.account != null && 
            payerContact.account.name != INDIVIDUAL_ACCOUNT_NAME &&
            (payer.CompanyName == null || payer.CompanyName.trim() == '' || !opSettings.gwop__COMPANY_NAME_INDICATES_ORG_PAYER__c)) {
                
            payerAccount = payerContact.account;
        }

        // set the match result property
        if (payerMatchResult == null && payerAccount != null) {
            payerMatchResult = gwop.OnlinePayment.MatchResult.ACCOUNT_MATCH;
            //system.debug('payerMatchResult: ' + payerMatchResult);
        }
        
        // if we don't have a match, create a payer account
        if (payerAccount == null) { 
            oldAccount = null;
            accountId = null;
            if (payer.companyName != null && payer.companyName != INDIVIDUAL_ACCOUNT_NAME)
                payerAccount = new Account(
                    Name = payer.companyName
                );
        } else {
            // create a copy of the existing account to compare later
            oldAccount = payerAccount.clone(true, true);
            accountId = payerAccount.Id;
        }
        
        // is the payer a company?
        if (companyIsPayer == null) companyIsPayer =
            ((payerAccount != null && payerContact == null) ||
            (opSettings.gwop__COMPANY_NAME_INDICATES_ORG_PAYER__c && payer.CompanyName != null && payer.CompanyName.trim() != '')
                && payer.companyName != INDIVIDUAL_ACCOUNT_NAME);
                        
        // for company opps, update account with any new data - overwrite as specified
        if ( companyIsPayer ) {
            if (payerAccount.BillingStreet == null || (payer.billingAddress.street != null && accountOverwrite.contains('address'))) {
                payerAccount.billingStreet = payer.billingAddress.street;
                payerAccount.billingCity = payer.billingAddress.city;
                payerAccount.billingState = payer.billingAddress.state;
                payerAccount.billingPostalCode = payer.billingAddress.zip;
                payerAccount.billingCountry = payer.billingAddress.country;
            }
            if (payerAccount.phone == null || (payer.billingAddress.phone != null && accountOverwrite.contains('phone')))
                payerAccount.phone = payer.billingAddress.phone;
            if (payerAccount.gwop__Online_Payer_Id__c == null)
                payerAccount.gwop__Online_Payer_Id__c = (payer.payerId == null) ? payer.email : payer.payerId;

            // fix the match result property
            if (payerMatchResult == gwop.OnlinePayment.MatchResult.CONTACT_MATCH) {
                payerMatchResult = gwop.OnlinePayment.MatchResult.ACCOUNT_MATCH;
                //system.debug('payerMatchResult: ' + payerMatchResult);
            }
        }
            
        // if we don't have a match yet, create a contact                       
        if (payerContact == null) {
            oldContact = null;
            contactId = null;
            if (payer.lastName != null)
                payerContact = new Contact(
                    firstName = payer.firstName,
                    lastName = payer.lastName,
                    email = payer.email,
                    leadsource = (payment.pmtProcessor == gwop.OnlinePayment.Processor.PAYPAL) ? 'Paypal' : 'Online Payment'                                
                );
        } else {
            // create a copy of the existing contact to compare later
            oldContact = payerContact.clone(true, true);
            contactId = payerContact.Id;
        }
        
        // set the match result property
        if (payerMatchResult == null) { 
            if (companyIsPayer && payerAccount != null)
                payerMatchResult = gwop.OnlinePayment.MatchResult.NEW_ACCOUNT;
            else if (payerContact != null)
                payerMatchResult = gwop.OnlinePayment.MatchResult.NEW_CONTACT;
            //system.debug('payerMatchResult: ' + payerMatchResult);                
        }

        // set contact fields - overwrite as specified
        if (payerContact != null) { 
            if (companyIsPayer || !opSettings.gwop__HOME_ADDRESS_IS_OTHER__c) {
                if (payerContact.mailingStreet == null || (payer.billingAddress.street != null && contactOverwrite.contains('address'))) {
                    payerContact.mailingStreet = payer.billingAddress.street;
                    payerContact.mailingCity = payer.billingAddress.city;
                    payerContact.mailingState = payer.billingAddress.state;
                    payerContact.mailingPostalCode = payer.billingAddress.zip;
                    payerContact.mailingCountry = payer.billingAddress.country;
                }
            } else {
                if (payerContact.otherStreet == null || (payer.billingAddress.street != null && contactOverwrite.contains('address'))) {
                    payerContact.otherStreet = payer.billingAddress.street;
                    payerContact.otherCity = payer.billingAddress.city;
                    payerContact.otherState = payer.billingAddress.state;
                    payerContact.otherPostalCode = payer.billingAddress.zip;
                    payerContact.otherCountry = payer.billingAddress.country;
                }
            }
            if (companyIsPayer) {
                if (payerContact.phone == null || (payer.billingAddress.phone != null && contactOverwrite.contains('phone')))
                    payerContact.phone = payer.billingAddress.phone;
            } else {
                if (payerContact.homePhone == null || (payer.billingAddress.phone != null && contactOverwrite.contains('phone')))
                    payerContact.homePhone = payer.billingAddress.phone;        
                if (payerContact.gwop__Online_Payer_Id__c == null && payer.payerId != null)
                    payerContact.gwop__Online_Payer_Id__c = payer.payerId;
            }
            if (payerContact.email == null || (payer.email != null && contactOverwrite.contains('email')))
                payerContact.email = payer.email;
        }
    
        // call the method to fill in custom contact or account fields
        if (payment.custom != null) {
            payment.custom = payment.custom.trim();
            
            // interpret JSON to set contact and account fields
            if (payment.custom.startsWith('{')) {
                try {
                    if (payerAccount != null)
                        payerAccount = (account)(updateSObjectFromJSON('account', (sobject)payerAccount, payment.custom));
                    if (payerContact != null)
                        payerContact = (contact)(updateSObjectFromJSON('contact', (sobject)payerContact, payment.custom));
                } catch (exception e) {
                    //system.debug('Failed to update online payer records from JSON in the custom property.');
                    //system.debug(e);
                }
            }
        }

        // if we have a payer, return true
        //system.debug(this);
        payerDataSaved = false; 
        //system.debug('fsetPayer() returns');
        //system.debug(payerAccount);
        //system.debug(payerContact);
        //return (payerAccount != null || payerContact != null);
    }

    /*------------------------------------------------------------------------------------
    * savePayerData method
    * creates (or updates) the account and/or contact for an online payment
    -------------------------------------------------------------------------------------*/ 
    public boolean fsavePayerData() {
        savePayerData();
        return true;
    }
    global virtual void savePayerData() {
        boolean success;

        if (payerDataSaved) { 
            success = true;
        } else {
            success = false;
            try {
                if (payerAccount != null) {
                    if (oldAccount == null) {
                        insert payerAccount;
                        accountId = payerAccount.Id;
                    } else if (payerAccount != oldAccount) {
                        update payerAccount;
                        oldAccount = payerAccount;  // in case we do this again
                        accountId = payerAccount.Id;
                    }
                }
                if (payerContact != null) {
                    if (oldContact == null) {
                        insert payerContact;
                        contactId = payerContact.id;
                    } else if (payerContact != oldContact) {
                        update payerContact;
                        oldContact = payerContact;  // in case we do this again
                        contactId = payerContact.id;
                    }
                }
                success = true;
            } catch (exception e) {
                throw new gwop.OnlinePayment.OnlinePaymentException('Could not save contact or account for online payment.', e);
            }               
            payerDataSaved = true;  
        }
        //return success;   
    }
    
    /*------------------------------------------------------------------------------------
    * processSinglePayment method
    * creates (or updates) an opportunity for an online payment
    * returns true if the processing was successful
    -------------------------------------------------------------------------------------*/
    public boolean fprocessSinglePayment() {
        processSinglePayment();
        return true;
    }   
    global virtual override void processSinglePayment() {
        
        boolean success = false;
        
        try {
            // make sure we have a payer
            if (payerContact != null || payerAccount != null || fsetPayer()) {
    
            //system.debug('found a payer ' + payerContact);
    
                // either create an opp, or save a copy of the existing one
                opportunity oldOpp;         
                if (paymentOpp != null) {       
                    oldOpp = paymentOpp.clone(true, true);
                } else {
                    if ((payment.pmtStatus == null || 
                        payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.COMPLETED ||
                        (opSettings.gwop__CREATE_PENDING_OPPS__c &&
                            (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.PENDING ||
                            payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.AUTHORIZED)) ||
                        (opSettings.gwop__CREATE_LOST_OPPS__c &&
                            (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.FAILED || 
                            payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.VOIDED || 
                            payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.DECLINED )))) {
                                    
                        paymentOpp = new Opportunity(
                            closeDate = system.today(),
                            recordTypeId = getPaymentRecordTypeId(
                                (payment.itemList != null && payment.itemList.size() > 0) ? payment.itemList[0].name : null ),
                            stagename = opSettings.gwop__OPP_STAGE_FOR_NEW_PAYMENTS__c,
                            gwop__online_transaction_id__c = payment.txnId 
                        );
                    }
                }   
                    
                if (paymentOpp != null && fsavePayerData()) {
        				
                    // set the opp values
                    string dateName = String.valueOf(system.today().year());
                    setOppValues( paymentOpp, recurringPayment, installment, dateName, oldOpp );
                                                            
                    // insert or update the opp
                    if (paymentOpp != null) {

                    	if (oldOpp == null) {
                            //system.debug(LoggingLevel.WARN,'inserting opp in fprocessSinglePayment.');
                            //system.debug(LoggingLevel.WARN,paymentOpp);
                            insert paymentOpp;
                        } else if (paymentOpp != oldOpp) {
                            //system.debug(LoggingLevel.WARN,'updating opp in fprocessSinglePayment.');
                            //system.debug(LoggingLevel.WARN,paymentOpp);
                            update paymentOpp;

                            // for completed payments, there may have been an unpaid amount                         
                            // query for the first unpaid payment of this amount underneath this recurring payment
                            if (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.COMPLETED) {
    
                                GWBase__oppPayment__c[] unpaidInstallment =  
                                    [select id, GWBase__opportunity__c, GWBase__date__c, GWBase__amount__c, GWBase__opportunity__r.GWBase__total_unpaid__c,
                                        GWBase__opportunity__r.id, GWBase__opportunity__r.amount, GWBase__opportunity__r.stagename 
                                        From GWBase__oppPayment__c where GWBase__paid__c = false and GWBase__written_off__c = false 
                                        and GWBase__opportunity__c = : paymentOpp.id 
                                        and GWBase__amount__c = : payment.totalAmount  
                                        order by GWBase__date__c limit 1];
                                        
                                if (!unpaidInstallment.isEmpty()) {
                            
                                    // mark the existing installment paid
                                    installment = unpaidInstallment[0];
                                    installment.GWBase__paid__c = true;
                                    installment.GWBase__date__c = system.today();
                                    installment.GWBase__Online_Transaction_ID__c = payment.txnId;
                                    installment.Credit_Card_Last_4_Digits__c = payment.last4digits;
                                    installment.Credit_Card_Expiration__c = payment.cardExpiration;
                                    try {
                                        //system.debug(LoggingLevel.WARN,'updating installment');
                                        //system.debug(LoggingLevel.WARN,installment);
                                        update installment;
                                    } catch (exception e) {
                                        throw new gwop.OnlinePayment.OnlinePaymentException('Could not update online payment record to paid.', e);
                                    }
                                }
                            }
                        }

                        if (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.PENDING ||
                            payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.AUTHORIZED) {
                            
                            // insert an unpaid installment
                            GWBase__oppPayment__c op = new GWBase__oppPayment__c(
                                GWBase__Amount__c = paymentOpp.Amount,
                                GWBase__date__c = paymentOpp.closeDate,
                                GWBase__isInstallment__c = true,
                                GWBase__opportunity__c = paymentOpp.id,
                                GWBase__opp_for_installment__c = paymentOpp.id,
                                GWBase__Online_Transaction_ID__c = payment.txnId,
                                GWBase__paid__c = false
                            );
                            insert op;
                            
                            // delete the mirror payment
                            GWBase__oppPayment__c[] mirrorOppPaymentsToDelete = [Select Id from GWBase__oppPayment__c 
                                where GWBase__IsInstallment__c=false and GWBase__Opportunity__c=:paymentOpp.id];
                            if (!mirrorOppPaymentsToDelete.isEmpty())
                                delete mirrorOppPaymentsToDelete;
    					
                        } else if (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.REVERSED) {

							if (paymentOpp != null && paymentOpp.id != null && payment.txnId != null) {
								
								// convert mirror payment to an installment payment
								if (installment != null && (!installment.GWBase__isInstallment__c || !installment.GWBase__paid__c)) {
					                installment.GWBase__isInstallment__c = true;
					                installment.GWBase__opp_for_installment__c = paymentOpp.id;
					                installment.GWBase__Online_Transaction_ID__c = payment.parentTxnId;
					                installment.GWBase__paid__c = true;
					                update installment;
								}
								if (refundInstallment == null) {
					                // insert a new installment payment for negative $$
					                refundInstallment = new GWBase__oppPayment__c(
					                    GWBase__Amount__c = 
					                    	(payment.totalAmount != null) ? -payment.totalAmount : 
					                    	(installment != null && installment.GWBase__amount__c != null) ? -installment.GWBase__amount__c : 
					                    	(paymentOpp.amount != null) ? -paymentOpp.amount : null,
					                    GWBase__date__c = system.today(),
					                    GWBase__check_date__c = system.today(),
					                    GWBase__isInstallment__c = true,
					                    GWBase__opportunity__c = paymentOpp.id,
					                    GWBase__opp_for_installment__c = paymentOpp.id,
					                    GWBase__Online_Transaction_ID__c = payment.txnId,
					                    GWBase__paid__c = true
					                );
					                insert refundInstallment;
								}
							}
                        }
                        
                        opportunityId = paymentOpp.id;
	                    success = true;     
                    }
                }
            }       
        } catch (exception e) {
            throw new gwop.OnlinePayment.OnlinePaymentException('Could not save online payment opportunity.', e);
        }               
                    
        //return success;
    }

    /*------------------------------------------------------------------------------------
    * startRecurringPayments method
    * creates either a Pledge with Installements (none paid), or a Recurring Payment profile
    * with a single open recurring Opportunity.
    *
    * note that in either case, nothing is marked paid by calling this method.  we assume
    * the processor will send a seperate notification for the first payment of the pledge
    * or subscription.
    *
    * returns true if the processing was successful
    -------------------------------------------------------------------------------------*/ 
    public boolean fstartRecurringPayments() {
        startRecurringPayments();
        return true;
    }
    global virtual override void startRecurringPayments() {
        boolean success = false;
        
        try {
            // don't create a record for a failed start 
            if (payment.pmtStatus == null || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.COMPLETED) { 
    
                //set a flag to indicate this transaction is for a pledge with a defined total payment amount and number of payments
                boolean isPledge = (payment.occurrences > 0) ? true : false;
        
                //for pledges with a defined number of occurrences, create one opp with payments
                if (isPledge) {
                    // make sure we have a payer
                    if (payerContact != null || payerAccount != null || fsetPayer()) {
            
                        // create the opp
                        if (payment.startDate == null) payment.startDate = system.today();
                        pledgeOpp = createPledgeOpp( payment.startDate );
                        
                        if (pledgeOpp != null && fsavePayerData()) {    
                            string dateName = String.valueOf(payment.startDate.year());
                            setOppValues(pledgeOpp, null, installment, dateName, null);
                            // setOppValues can't always derive whether this is a pledge, so force its stage.
                            pledgeOpp.StageName = GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE;
                                                
                            // save the opp
                            //system.debug('Saving pledge opportunity, and installment records.');
                            // get installments through to be created based on occurrences - have do do this before inserting the opp to get total
                            futureInstallments = createInstallmentList( pledgeOpp, payment.startDate );
                            
                            // now insert the opp, which will get us an Id
                            //system.debug('inserting opp in fstartRecurringPayments.');
                            //system.debug(pledgeOpp);                      
                            insert pledgeOpp;
        
                            // set the opp Id for the list of installments, then insert them
                            for (GWBase__oppPayment__c op : futureInstallments) {
                                op.GWBase__opportunity__c = pledgeOpp.id;
                                op.GWBase__opp_for_installment__c = pledgeOpp.id;
                                //op.GWBase__Online_Transaction_ID__c = payment.txnId;
                            }
                            insert futureInstallments;
                            //system.debug(futureInstallments);
                            
                            // remove the obsolete mirror payment
                            GWBase__oppPayment__c[] mirrorOppPaymentsToDelete = [Select Id from GWBase__oppPayment__c 
                                where GWBase__IsInstallment__c=false and GWBase__Opportunity__c=:pledgeOpp.id];
                            if (!mirrorOppPaymentsToDelete.isEmpty())
                                delete mirrorOppPaymentsToDelete;
        
                            // set the opp id to send back to the payment notification record
                            opportunityId = pledgeOpp.id;
                            success = true;                 
                        }               
                    }           
                    return; // success;
                    
                } else {
                    // make sure we have a payer
                    if (fsetPayer()) {
                
                        // for an update, we will cancel the existing recurring payment and create a new one
                        GWBase__recurring_payment_profile__c oldRP = (recurringPayment != null) ? recurringPayment : null;
            
                        // get a new recurring payment
                        recurringPayment = createRecurringPayment( payment.startDate );
                        
                        if (recurringPayment != null && fsavePayerData()) { 
            
                            // set the id of the payer
                            if (companyIsPayer) 
                                recurringPayment.GWBase__account__c = accountId;
                            else    
                                recurringPayment.GWBase__Contact__c = contactId;
            
                            // save the opp
                            //system.debug('Saving recurring payment profile.');
                            //system.debug(recurringPayment);
                            // insert the new recurring pmt
                            insert recurringPayment;
                            
                            // create the opp (unpaid)
                            paymentOpp = createRecurringPaymentOpp( recurringPayment, payment.startDate, false );                       
                            
                            // if there was an existing payment, we need to stop it before inserting the new one
                            if (oldRP != null) closeRecurringPayment(oldRP, true);
        
                            // now insert the opp, which will get us an Id
                            //system.debug('inserting opp in fstartRecurringPayments.');
                            //system.debug(paymentOpp);                     
                            insert paymentOpp;
                                
                            // set the opp id to send back to the payment notification record
                            //if we add N number of open opps in the future, setting log to oppId should go away?
                            opportunityId = paymentOpp.id;
                            success = true;                 
                        }
                    }                       
                }
            }
        } catch (exception e) {
            throw new gwop.OnlinePayment.OnlinePaymentException('Could not save recurring online payment records.', e);
        }   
        //return success;
    }   
    
    /*------------------------------------------------------------------------------------
    * processRecurringPayment method
    * creates (or updates) an opportunity for an online payment associated with recurring opp
    * returns true if the processing was successful
    -------------------------------------------------------------------------------------*/ 
    public boolean fprocessRecurringPayment() {
        processRecurringPayment();
        return true;
    }
    global virtual override void processRecurringPayment() {
        boolean success = false;
                    
        // refunds do not affect the recurring transaction
        if (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.REVERSED) {
        	processSinglePayment();
        	return;
    	}

        // need a recurring Id, and also someone to own the payment
        if (payment.recurringTxnId != null && fsetPayer()) {
            id oppId;
            
            //first, process open-ended ongoing recurring payments
            if (pledgeOpp == null) {
            
                // create a new recurring payment record if needed; also make sure that
                // the amount of this payment matches the amount of the recurring transaction
                // then save payer data before continuing
                if (((recurringPayment != null && payment.totalAmount == recurringPayment.GWBase__amount__c) ||
                    fstartRecurringPayments()) && fsavePayerData()) {
                    
                    if (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.AUTHORIZED) {
                        // don't do anything to opp or payments, but report success - because nothing is wrong
                        success = true;
                        
                    } else if (payment.pmtStatus == null || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.COMPLETED) {
    
                        // make sure we do not have a repeat transaction id
                        if (paymentOpp == null || !paymentOpp.isWon) {
                    
                            // query for the first unpaid opp of this amount underneath this recurring payment
                            //only looks for one now, may change to multiple if we allow N number of open opps in future
                            Opportunity[] unpaidOpp =  
                                [select id, closedate, amount, stagename, type
                                    From Opportunity where stagename = : GWBase.ONEN_Constants.OPP_DEFAULT_RECURRING_STAGE  
                                    and GWBase__recurring_payment_profile__c = : recurringPayment.id 
                                    and amount = : payment.totalAmount  
                                    order by closedate limit 1];
            
                            if (!unpaidOpp.isEmpty()) {
                                
                                // mark the existing opportunity paid
                                paymentOpp = unpaidOpp[0];
                                paymentOpp.stageName = opSettings.gwop__Opp_Stage_for_Closed_Opps__c;
                                paymentOpp.closedate = system.today();
                                paymentOpp.gwop__Online_Transaction_ID__c = payment.txnId;
                                paymentOpp.Type = getPaymentType(payment.pmtType, payment.pmtProcessor);
                                try {
                                    //system.debug('updating opp in fprocessRecurringPayment.');
                                    //system.debug(paymentOpp);
                                    update paymentOpp;
            
                                    // set the opp id to send back to the payment notification record
                                    opportunityId = paymentOpp.id;
            
                                } catch (exception e) {
                                    throw new gwop.OnlinePayment.OnlinePaymentException('Could not update recurring opportunity record to paid.', e);
                                }
                            } else {                    
                                // create a new paid opp 
                                paymentOpp = createRecurringPaymentOpp( recurringPayment, payment.startDate, true );                        
                                
                                //we don't need to create a new open opp in the future because this is handled by a trigger in GWBase 
            
                                try {
                                    // now insert the opp, which will get us an Id
                                    //system.debug('inserting opp in fprocessRecurringPayment.');
                                    //system.debug(paymentOpp);
                                    insert paymentOpp;
                
                                    // set the opp id to send back to the payment notification record
                                    opportunityId = paymentOpp.id;
            
                                } catch (exception e) {
                                    throw new gwop.OnlinePayment.OnlinePaymentException('Could not save recurring payment opportunity.', e);
                                }
                            }
                            
                            success = true;
                        }
                    }
                }
            //now process pledge payments if we did not find an open-ended recurring
            } else {
                if ((pledgeOpp != null  || fstartRecurringPayments()) 
                    && fsavePayerData()) {
                
                    if (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.AUTHORIZED) {
                        // don't do anything to opp or payments, but report success - because nothing is wrong
                        success = true;
                                                
                    } else if (payment.pmtStatus == null || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.COMPLETED) {
                    
                        // make sure we do not have a repeat transaction id
                        if (installment == null) {
                    
                            // query for the first unpaid payment of this amount underneath this recurring payment
                            GWBase__oppPayment__c[] unpaidInstallment =  
                                [select id, GWBase__opportunity__c, GWBase__date__c, GWBase__amount__c, GWBase__opportunity__r.GWBase__total_unpaid__c,
                                    GWBase__opportunity__r.id, GWBase__opportunity__r.amount, GWBase__opportunity__r.stagename 
                                    From GWBase__oppPayment__c where GWBase__paid__c = false and GWBase__written_off__c = false 
                                    and GWBase__opportunity__r.gwop__Online_Pledge_Transaction_Id__c = : payment.recurringTxnId 
                                    and GWBase__amount__c = : payment.totalAmount  
                                    order by GWBase__date__c limit 1];
            
                            boolean fullyPaid = false;
            
                            if (!unpaidInstallment.isEmpty()) {
                                
                                // mark the existing installment paid
                                installment = unpaidInstallment[0];
                                installment.GWBase__paid__c = true;
                                installment.GWBase__date__c = system.today();
                                installment.GWBase__Online_Transaction_ID__c = payment.txnId;
                                installment.Credit_Card_Last_4_Digits__c = payment.last4digits;
                                installment.Credit_Card_Expiration__c = payment.cardExpiration;
                                try {
                                    //system.debug('updating installment');
                                    //system.debug(installment);
                                    update installment;
            
                                    // set the opp id to send back to the payment notification record
                                    opportunityId = installment.GWBase__opportunity__c;
                                    paymentOpp = installment.GWBase__opportunity__r;
            
                                    fullyPaid = (installment.GWBase__amount__c == installment.GWBase__opportunity__r.GWBase__total_unpaid__c);
            
                                } catch (exception e) {
                                    throw new gwop.OnlinePayment.OnlinePaymentException('Could not update pledge installment record to paid.', e);
                                }
                            } else {
                                // so we found no unpaid installments, so we now just treat this as a single payment
                                payment.recurringtxnId = null; // clear so we won't match the original pledge.
                                //return fprocessSinglePayment();
                                processSinglePayment();
                                return;
                                /*                  
                                // create a new opp with one payment paid
                                paymentOpp = createRecurringPaymentOpp( recurringPayment, payment.startDate, true );    
                                //paymentOpp.StageName = opSettings.gwop__Opp_Stage_for_Closed_Opps__c;             
            
                                try {
                                    // now insert the opp, which will get us an Id
                                    //system.debug('inserting opp in fprocessRecurringPayment.');
                                    //system.debug(paymentOpp);
                                    insert paymentOpp;
                
                                    // set the opp id to send back to the payment notification record
                                    opportunityId = paymentOpp.id;
            
                                } catch (exception e) {
                                    throw new gwop.OnlinePayment.OnlinePaymentException('Could not save recurring online payment records.', e);
                                }
                                */
                            }
                            success = true;
                        }
                    }
                }
            }
        }
    }

    /*------------------------------------------------------------------------------------
    * cancelRecurringPayments method
    * finds and marks the specified recurring payment opp(s) as closed or written off
    * returns true if the processing was successful
    -------------------------------------------------------------------------------------*/ 
    public boolean fcancelRecurringPayments() {
        cancelRecurringPayments();
        return true;
    }   
    global virtual override void cancelRecurringPayments() {
        boolean success = false;
        if (payment.recurringTxnId != null && fsetPayer() && (recurringPayment != null || pledgeOpp != null)) {
            
            //system.debug('Canceling the recurring payment or pledge.');
            try {
                if (recurringPayment != null ) {
                    closeRecurringPayment(recurringPayment, false);
                } else {
                    closePledge(pledgeOpp, false);
                }
                success = true;
            } catch (exception e) {
                throw new gwop.OnlinePayment.OnlinePaymentException('Could not cancel recurring online payment records.', e);
            }                       
        }       
        //return success;   
    }

    /*------------------------------------------------------------------------------------
    * createRecurringPayment method
    * used in both recurring payment methods
    -------------------------------------------------------------------------------------*/
    global virtual GWBase__recurring_payment_profile__c createRecurringPayment( date pmtStartDate ) {

        if (pmtStartDate == null) pmtStartDate = system.today();
        
        GWBase__recurring_payment_profile__c rp = new GWBase__recurring_payment_profile__c();
        rp.GWBase__type__c = ((payment.pmtProcessor == gwop.OnlinePayment.Processor.PAYPAL ? 'Paypal' : 
            (payment.pmtProcessor == gwop.OnlinePayment.Processor.AUTHNET ? 'Authorize.net' : 'Other')));
        rp.GWBase__Transaction_Id__c = payment.recurringTxnId;
        rp.GWBase__Payment_Period__c = 
            (payment.pmtPeriod == gwop.OnlinePayment.recurringPeriod.DAY) ? 'Day' : 
            (payment.pmtPeriod == gwop.OnlinePayment.recurringPeriod.WEEK) ? 'Week' : 
            (payment.pmtPeriod == gwop.OnlinePayment.recurringPeriod.YEAR) ? 'Year' : 'Month';
        rp.GWBase__Frequency__c = (payment.frequency == null) ? 1 : payment.frequency; 
        rp.GWBase__start_Date__c = system.today();
        //rp.Occurrences__c = payment.occurrences; 
        rp.GWBase__Amount__c = payment.totalAmount;
            
        // fill in credit card info
        rp.Credit_Card_Last_4_Digits__c = payment.last4digits;
        rp.Credit_Card_Expiration__c = payment.cardExpiration;

        // build the name in the form "John and Jane Doe Monthly Payment"
        if (companyIsPayer || payerContact == null) {
            rp.name = payerAccount.Name; 
        } else {    
            rp.name = (payerContact.GWBase__householdName__c != null) ? payerContact.GWBase__householdName__c : 
                ((payerContact.FirstName == null) ? payerContact.LastName : (payerContact.firstName + ' ' + payerContact.lastName));
        }
        rp.name += ((rp.GWBase__Payment_Period__c == 'Month' && rp.GWBase__Frequency__c == 1) ? ' Monthly' : ' Recurring') + ' Payment';
        
        return rp; 
    }

    /*------------------------------------------------------------------------------------
    * createRecurringPaymentOpp method
    * used in both opp creation methods
    -------------------------------------------------------------------------------------*/
    global virtual opportunity createRecurringPaymentOpp( GWBase__recurring_payment_profile__c rp, date pmtStartDate, boolean isPaid ) {

        if (pmtStartDate == null) pmtStartDate = system.today();

        opportunity o = new Opportunity(
            type = getPaymentType(payment.pmtType, payment.pmtProcessor),
            closeDate = system.today(),
            recordTypeId = getPaymentRecordTypeId(
                (payment.itemList != null && payment.itemList.size() > 0) ? payment.itemList[0].name : null ),
            GWBase__recurring_payment_profile__c = rp.id,
            amount = rp.GWBase__Amount__c,
            gwop__Online_transaction_id__c = payment.txnId
        );
        
        // get the date string for the opp name
        string dateName = (String.valueOf(String.valueOf(pmtStartDate.year())));        
        setOppValues(o, rp, installment, dateName, null);
        o.Stagename = isPaid ? opSettings.gwop__Opp_Stage_for_Closed_Opps__c : GWBase.ONEN_Constants.OPP_DEFAULT_RECURRING_STAGE;
        return o;
    }
    
    /*------------------------------------------------------------------------------------
    * createPledgeOpp method
    * 
    * creates (but does not save) the opportunity to represent a pledge.
    * caller must call setOppValues on this opp after fsavePayerData, before saving the opp. 
    -------------------------------------------------------------------------------------*/ 
    global virtual opportunity createPledgeOpp( date pmtStartDate ) {

        if (pmtStartDate == null) pmtStartDate = system.today();

        opportunity o = new Opportunity(
            type = getPaymentType(payment.pmtType, payment.pmtProcessor),
            closeDate = system.today(),
            recordTypeId = getPaymentRecordTypeId(
                (payment.itemList != null && payment.itemList.size() > 0) ? payment.itemList[0].name : null ),
            gwop__Online_pledge_transaction_id__c = (payment.occurrences > 0 && payment.recurringTxnId != null) ? payment.recurringTxnId : null
        );
        
        // get the date string for the opp name
        string dateName = (String.valueOf(pmtStartDate.month()) + '/' + String.valueOf(pmtStartDate.year()));

        return o;
    }

    /*------------------------------------------------------------------------------------
    * createInstallmentList method
    * set up payments to the end of the fiscal year, and then set the total opp amount
    -------------------------------------------------------------------------------------*/
    global virtual GWBase__oppPayment__c[] createInstallmentList( opportunity pmtOpp, date pmtStartDate ) { 
                        
        list<GWBase__OppPayment__c> listPmt = new list<GWBase__OppPayment__c>();

        decimal decOppTotal = 0; 
        if (pmtStartDate == null) pmtStartDate = system.today();
        date dateNextPmt = pmtStartDate;
        
        string period = 
            (payment.pmtPeriod == gwop.OnlinePayment.recurringPeriod.DAY) ? 'Day' : 
            (payment.pmtPeriod == gwop.OnlinePayment.recurringPeriod.WEEK) ? 'Week' : 
            (payment.pmtPeriod == gwop.OnlinePayment.recurringPeriod.YEAR) ? 'Year' : 'Month';  
        
        for (integer i = 0; i < payment.occurrences; i++) {
            listPmt.add(
                new GWBase__OppPayment__c(
                    GWBase__Amount__c = payment.totalAmount,
                    GWBase__Date__c = dateNextPmt,
                    GWBase__isInstallment__c = true,
                    GWBase__paid__c = false
                )
            );
            decOppTotal += payment.totalAmount;
            
            dateNextPmt = 
                (period == 'Day') ? dateNextPmt.addDays(payment.frequency) :
                (period == 'Week') ? dateNextPmt.addDays(payment.frequency * 7) :
                (period == 'Year') ? dateNextPmt.addYears(payment.frequency) :
                dateNextPmt.addMonths(payment.frequency); 

        }   
            
        // set the opp amount
        pmtOpp.Amount = decOppTotal;
        return listPmt;
    }

    /*------------------------------------------------------------------------------------
    * closeRecurringPayment method
    * find unpaid opps, delete them, much this logic now handled by trigger in GWBase
    * also mark the rp with an end date of today and clear its id
    * used in a couple recurring payment methods
    -------------------------------------------------------------------------------------*/ 
    global virtual void closeRecurringPayment(GWBase__recurring_payment_profile__c rp, boolean clearId) {
        if (rp.id != null) {
            // mark the recurring payment as complete
            rp.GWBase__end_date__c = system.today();
            if (clearId) rp.GWBase__transaction_id__c = null;
            update rp;
        }
    }
    
    /*------------------------------------------------------------------------------------
    * closePledge method
    * find opps with unpaid payments, mark them as written off
    -------------------------------------------------------------------------------------*/ 
    global virtual void closePledge(Opportunity pledge, boolean clearId) {
        if (pledge.id != null) {
            // query for all the payments for opps with unpaid payments under this pledge id and mark them as written off since they were previously receivables (and realized on the books)
            GWBase__oppPayment__c[] paymentsToWriteOff = [select id, GWBase__opportunity__c, GWBase__paid__c, GWBase__amount__c, 
                GWBase__opportunity__r.id, GWBase__opportunity__r.amount, GWBase__opportunity__r.GWBase__Total_Paid__c 
                From GWBase__OppPayment__c where GWBase__paid__c = false and GWBase__written_off__c = false 
                and GWBase__opportunity__r.id = : pledge.id limit 800 ];  
            
            // walk through the payments and mark them as written off
            for (GWBase__oppPayment__c op : paymentsToWriteOff) {
                op.GWBase__Written_Off__c = true;
            }
                
            //if we never received a payment for this pledge, mark it as Closed Lost
            if (pledge.GWBase__Total_Paid__c == 0) {
                pledge.stageName = opSettings.gwop__Opp_Stage_for_Lost_Opps__c;
            } else {
                // need to update the opp's amount, so our rollups are correct.
                pledge.Amount = pledge.GWBase__Total_Paid__c;
                pledge.stageName = opSettings.gwop__Opp_Stage_for_Closed_Opps__c ;
            }
                
            // save all the changes
            if (!paymentsToWriteOff.isEmpty()) 
                update paymentsToWriteOff;
            
            // update the pledge opp, don't reset the amount because this was already realized on the books as a receivable with now written off payments
            if (clearId) pledge.gwop__Online_pledge_transaction_id__c = null;
            update pledge;
        }
    }

    /*------------------------------------------------------------------------------------
    * setOppValues method
    * used in all opp creation methods
    -------------------------------------------------------------------------------------*/
    global virtual void setOppValues(opportunity o, GWBase__recurring_payment_profile__c rp, 
        GWBase__oppPayment__c inst, string dateName, opportunity oldOpp ) { 
        boolean isUpdate = (oldOpp != null);
        boolean oppWasAlreadyClosed = (isupdate && oldOpp.isWon);
        string oppSuffix = GWBase.GW_RecTypes.GetRecordTypeName('Opportunity', o.RecordTypeId); 
        
        //system.debug('setOppValues payerContact');
        //system.debug(payerContact);
        //system.debug('setOppValues payerAccount');
        //system.debug(payerAccount);
        //system.debug('setOppValues companyIsPayer: ' + companyIsPayer);
        
        // set name and role for company or individual - our trigger will create a contact role
        if (companyIsPayer || payerContact == null) {
            o.AccountId = payerAccount.Id;
            if (!isUpdate && payerContact != null) {
                o.GWBase__CR_Contact_Id__c = payerContact.Id;
                o.GWBase__CR_Contact_Role__c = GWBase.ONEN_Constants.OPP_ORG_GIFT_DONOR_ROLE;
                o.GWBase__CR_HHRoles__c = false;
            }
            //this should use GWBase opp naming in ONEN_OpportunityMaintenance
            //o.Name = payerAccount.Name +  ' ' + dateName + ' ' + oppSuffix;
            
        } else {
            
            if (/* !isUpdate  && */ payerContact != null) {
                //system.assertEquals(contactId, payerContact.Id);
                //system.assert(contactId != null);
                o.GWBase__CR_Contact_Id__c = payerContact.Id;
                o.GWBase__ContactId__c = payerContact.Id;   //  have to populate this too, for the new conroles architecture
                o.GWBase__CR_Contact_Role__c = GWBase.ONEN_Constants.OPP_GIFT_DONOR_ROLE(GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_CONTACT);
                o.GWBase__CR_HHRoles__c = true;
            }
            
            //this should use GWBase opp naming in ONEN_OpportunityMaintenance              
            //o.Name = 
            //  ((payerContact.GWBase__householdName__c != null) ? payerContact.GWBase__householdName__c :
            //  (payerContact.firstName == null) ? payerContact.lastName : 
            //  (payerContact.FirstName + ' ' + payerContact.lastName)) +  ' ' + 
            //  dateName + ' ' + oppSuffix;             
        }
    
        // set the opp stage based on the payment status
        // four scenarios: refund, single payment, pledge with installments, recurring payment
	       	//system.debug(logginglevel.warn, 'SETTING OPP STAGE');
	       	//system.debug(logginglevel.warn, payment);
	       	//system.debug(logginglevel.warn, inst);
	       	//system.debug(logginglevel.warn, rp);
	       	//system.debug(logginglevel.warn, o);
        
        if (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.REVERSED) {  // refund
	       	
	       	if (o.stageName != GWBase.ONEN_Constants.OPP_DEFAULT_RECURRING_STAGE && 
	       		o.stageName != GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE) {
	       		
	            o.stageName = 
	                (payment.totalAmount == null || inst == null || payment.totalAmount == inst.gwbase__amount__c) ? 
	                opSettings.gwop__Opp_Stage_for_Refunds__c : opSettings.gwop__Opp_Stage_for_Partial_Refunds__c ; 
            	//system.debug(logginglevel.warn, 'setOppValues assumes Refund with stage=' + o.StageName);
	       	}
        } else if (rp == null && inst == null) { // single payment
            o.stageName = 
                ((payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.PENDING || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.AUTHORIZED) && !oppWasAlreadyClosed) ? 
                opSettings.gwop__OPP_STAGE_FOR_PENDING_PAYMENTS__c : 
                (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.FAILED || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.VOIDED || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.DECLINED ) ? 
                opSettings.gwop__Opp_Stage_for_Lost_Opps__c : 
                opSettings.gwop__Opp_Stage_for_Closed_Opps__c;
            //system.debug(logginglevel.warn, 'setOppValues assumes Single Payment with stage=' + o.StageName);

	        // set the amount
	        o.amount = payment.totalAmount;

        } else if (rp == null) { // pledge with installments 
            o.stageName = 
                ((payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.PENDING || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.AUTHORIZED) && !oppWasAlreadyClosed) ? 
                opSettings.gwop__OPP_STAGE_FOR_PENDING_PAYMENTS__c : 
                (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.FAILED || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.VOIDED || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.DECLINED ) ? 
                opSettings.gwop__Opp_Stage_for_Lost_Opps__c :                 
                GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE;                
            //system.debug(logginglevel.warn, 'setOppValues assumes Pledge with Installments with stage=' + o.StageName);

	        // set the amount
    	    o.amount = (o.amount == null) ? payment.totalAmount : o.amount;

        } else { // recurring payment
            o.stageName = 
                ((payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.PENDING || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.AUTHORIZED) && !oppWasAlreadyClosed) ? 
                GWBase.ONEN_Constants.OPP_DEFAULT_RECURRING_STAGE : 
                (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.FAILED || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.VOIDED || payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.DECLINED || (isUpdate && payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.REVERSED)) ? 
                opSettings.gwop__Opp_Stage_for_Lost_Opps__c : 
                opSettings.gwop__Opp_Stage_for_Closed_Opps__c;
            //system.debug(logginglevel.warn, 'setOppValues assumes Recurring Payment with stage=' + o.StageName);

	        // set the amount
    	    o.amount = payment.totalAmount;
        }       
                
        // set the type
        o.Type = getPaymentType(payment.pmtType, payment.pmtProcessor); 
                
        // build a description field to display other payment data
        if (payment.pmtStatus == gwop.OnlinePayment.PaymentStatus.REVERSED) {
	        if (payment.memo != null && (o.description == null || !o.description.contains('Refund Memo')))
	        	o.description = ((o.description == null ? '' : o.description) + '\nRefund Memo:\n' + payment.memo).trim();
        } else {
	        string descr = '' + 
	            ((payment.currencyCode != null) ? '\nCurrency Code: ' + payment.currencyCode : '') +
	            ((payment.fee != null) ? '\nPayment Fee: ' + payment.fee.format() : '') + 
	            ((payment.tax != null) ? '\nTax: ' + payment.tax.format() : '') + 
	            ((payment.shippingDiscount != null) ? '\nShipping Discount: ' + payment.shippingDiscount.format() : '') + 
	            ((payment.reasonCode != null) ? '\nReason for transaction pending/failure: ' + payment.reasonCode : '') + 
	            ((payment.invoice != null) ? '\nInvoice # ' + payment.invoice : '');
	                    
	        // look for multiple items
	        // we could create opportunity products or other child records for items, but we'll just log them 
	        if (payment.itemList != null && payment.itemList.size() > 1) {
	            descr += '\nItems ordered: ';
	            for (gwop.OnlinePayment.Item itm : payment.itemList) 
	                descr += '\n  ' + ((itm.quantity != null) ? (itm.quantity.format() + ' ') : '') + 
	                    itm.name + ((itm.code != null) ? (' (' + itm.code + ')') : '');
	        } 
	                
	        // finish the description
	        if (payment.memo != null) descr += '\nPayment Memo:\n' + payment.memo;
	        if (descr != '') o.description = descr.trim();
        }
        
        // fill in credit card info
        if (payment.last4digits != null) o.Credit_Card_Last_4_Digits__c = payment.last4digits;
        if (payment.cardExpiration != null) o.Credit_Card_Expiration__c = payment.cardExpiration;

        // fill in custom payment fields
        if (payment.custom != null) {
            payment.custom = payment.custom.trim();
            
            // if custom is a campaign id, associate the opp with this campaign
            if (payment.custom.startsWith('701')) {
                try {
                    o.campaignId = payment.custom;
                } catch (exception e) { 
                    //system.debug('Failed to set payment campaign.');
                }
            
            } else if (payment.custom.startsWith('{')) {

                // interpret JSON to set payment fields
                try {
                    if (rp != null) {
                        rp = (GWBase__recurring_payment_profile__c)(updateSObjectFromJSON('GWBase__recurring_payment_profile__c', (sobject)rp, payment.custom));
                    }
                    if (o != null) {
                        o = (opportunity)(updateSObjectFromJSON('opportunity', (sobject)o, payment.custom));
                    }
                    if (inst != null) {
                        inst = (GWBase__oppPayment__c)(updateSObjectFromJSON('GWBase__oppPayment__c', (sobject)inst, payment.custom));
                    }
                } catch (exception e) {
                    //system.debug('Failed to update online payment records from JSON in the custom property.');
                    //system.debug(e);
                }
            }
        }
        
        if (payment.CampaignId != null) o.campaignId = payment.campaignId;
        
        //system.debug('leaving setOppValues');
        //system.debug(o);
    }


    /*------------------------------------------------------------------------------------
    * getPaymentRecordTypeId method
    * returns the record type id for a given item name, or else the default item name
    -------------------------------------------------------------------------------------*/
    global id getPaymentRecordTypeId( string itemName ) {
        string recType = opSettings.gwop__DEFAULT_RECORD_TYPE__c;
        
        if (itemName != null && opSettings.gwop__ITEM_RECORD_TYPES__c != null) {
            for (string pair : opSettings.gwop__ITEM_RECORD_TYPES__c.split(';')) {
                if (pair.contains(',')) {
                    string[] s = pair.split(',');
                    if (s[0].trim() == itemName) {
                        recType = s[1].trim();
                        break;
                    }
                }
            }
        }
        return GWBase.GW_RecTypes.GetRecordTypeId('Opportunity', recType);
    }

    /*------------------------------------------------------------------------------------
    * updateSObjectFromJSON method
    * looks for field values in a json string and sets them in an sobject
    * 
    * JSON in the 'custom' property can take one of two forms:
    *   you can specify generic field name/value pairs for any object, or set fields on a
    *   specific object by setting a value for the object name (e.g. contact, account) 
    *   and then nesting JSON with field values 
    * FORM 1:
    *   {"leadsource": "Secret", "my_custom_field__c": "Sauce"}
    * FORM 2: 
    *   {"contact": {"leadsource": "Secret", "my_custom_field__c": "Sauce"}, 
    *       "account": {"description": "Special" },
    *       "opportunity": {"leadsource": "Secret", "my_custom_field__c": "Sauce"}, 
    *       "GWBase__oppPayment__c": {"my_custom_field__c": "something"} }
    -------------------------------------------------------------------------------------*/
    global static sobject updateSObjectFromJSON(string objName, sobject o, string js) {

		try {
	        JSONParser jp = JSON.createParser(js);
	        string subobject; 
	        while (jp.nextToken() != null) {
	            if (jp.getCurrentToken() == JSONToken.END_OBJECT) {
	                if (subobject == null) {
	                    break;
	                } else {
	                    subobject = null;
	                    jp.nextToken();
	                }
	            }
	            if (jp.getCurrentToken() == JSONToken.FIELD_NAME) {
	                string fld = jp.getText();
	                
	                
	                jp.nextToken();
	                if (jp.getCurrentToken() == JSONToken.START_OBJECT) {
	                    subobject = fld;
	                } else if (subobject == null || subobject == objName) {
	                    try {
	                    	
	                    	// for each type, convert data to the right type of the destination field
	                    	string fldType = GWBase.GW_Describe.getFieldType(objname, fld);
	                    	
	                        if (jp.getCurrentToken() == JSONToken.VALUE_STRING) {
	                            String s = jp.getText();
	                            if (fldType == 'INTEGER') {
	                            	o.put(fld, integer.valueOf(s));
	                            } else if (fldType == 'PERCENT' || fldType == 'CURRENCY') {
	                            	o.put(fld, decimal.valueOf(s));
	                            } else if (fldType == 'DOUBLE') {
	                            	o.put(fld, double.valueOf(s));
	                           	} else if (fldType == 'BOOLEAN'){
	                            	if (s == 'on' || s == 'yes' || s == 'true') {
	                            		o.put(fld, true);
	                            	} else if (s == 'off' || s == 'no' || s == 'false') {
	                            		o.put(fld, false);
	                            	}
	                            } else if (fldType == 'DATE') {
	                            	if (s != '' && s.contains('/')) {
	                            		o.put(fld, date.parse(s));
	                            	} else if (s != '' && s.contains('-')) {
	                            		o.put(fld, date.valueOf(s));
	                            	}
	                            } else if (fldType == 'DATETIME') {	
	                            	if (s != '' && s.contains('/')) {
	                            		o.put(fld, datetime.parse(s));
	                            	} else if (s != '' && s.contains('-')) {
	                            		o.put(fld, datetime.valueOfGmt(s));
	                            	}
	                            } else {
	                            	o.put(fld, s);
	                            }

	                        } else if (jp.getCurrentToken() == JSONToken.VALUE_NULL) {
	                            o.put(fld, null);
	                        } else if (jp.getCurrentToken() == JSONToken.VALUE_FALSE) { 
	                            if (fldType == 'BOOLEAN') {
	                            	o.put(fld, false);
	                            } else {
	                            	o.put(fld, 'False');
	                            }
	                        } else if (jp.getCurrentToken() == JSONToken.VALUE_TRUE) {
	                            if (fldType == 'BOOLEAN') {
	                            	o.put(fld, true);
	                            } else {
	                            	o.put(fld, 'True');
	                            }
	                        } else if (jp.getCurrentToken() == JSONToken.VALUE_NUMBER_INT) {
	                            if (fldType == 'INTEGER') {
	                            	o.put(fld, jp.getIntegerValue());
	                            } else if (fldType == 'PERCENT' || fldType == 'CURRENCY') {
	                            	o.put(fld, decimal.valueOf(jp.getIntegerValue()));
	                            } else if (fldType == 'DOUBLE') {
	                            	o.put(fld, double.valueOf(jp.getIntegerValue()));
	                           	} else {
	                            	o.put(fld, string.valueOf(jp.getIntegerValue()));
	                            }
	                        } else if (jp.getCurrentToken() == JSONToken.VALUE_NUMBER_FLOAT) {
	                            decimal d = jp.getDecimalValue();
	                            if (fldType == 'PERCENT' || fldType == 'CURRENCY') {
	                            	o.put(fld, d);
	                            } else if (fldType == 'INTEGER') {
	                            	o.put(fld, d.round());
	                            } else if (fldType == 'DOUBLE') {
	                            	o.put(fld, d.doubleValue());
	                            } else {
	                            	o.put(fld, string.valueOf(d));
	                            }
	                            
	                            
	                        }
	                        //system.debug('Updated field: ' + objName + '.' + fld);
	                    } catch (exception e) {
				            system.debug(logginglevel.error,
				            	'Could not update field \'' + objName + '.' + fld + '\' from custom payment data.');
	                    }
	                }
	            }
	        }
        } catch (exception e) {
            system.debug(logginglevel.error, 'Could not update object \'' + objName + '\' from custom payment data.');
        }
        return o;
    }

    /*------------------------------------------------------------------------------------
    * getPaymentType method
    * returns the name of the form of payment, which we use to populate the op type 
    -------------------------------------------------------------------------------------*/     
    global virtual string getPaymentType(gwop.OnlinePayment.PaymentType pt, gwop.OnlinePayment.Processor pp) {
        
        // customize or override if you want different opp type values
        return 
            (pt==gwop.OnlinePayment.PaymentType.CREDITCARD) ? 'Credit Card' : 
            (pt==gwop.OnlinePayment.PaymentType.ECHECK) ? 'E-Check' :
            (pt==gwop.OnlinePayment.PaymentType.EFT) ? 'Electronic Funds Transfer' :
            
            // if none of those types, look at the Processor 
            (pp == gwop.OnlinePayment.Processor.PAYPAL) ? 'Paypal' : 
                (pp == gwop.OnlinePayment.Processor.AUTHNET) ? 'Authorize.net' : 
                'Online Payment';
    }

    /*------------------------------------------------------------------------------------
    * fiscalYear method
    * returns the fiscal year of a date
    -------------------------------------------------------------------------------------*/ 
    global integer fiscalYear(date d) {
        // get the fiscal year start month if it isn't filled in
        if (fysm == null)
            fysm = [select fiscalYearStartMonth from organization limit 1].fiscalYearStartMonth;
        
        return //(fysm == null) ? null :
            //(fysm == 1) ? d.year() :
            d.addMonths(1-fysm).year();
    }

}