@isTest
public with sharing class PaymentToSalesforceGWTest {

    static testMethod void testMatching () { 
        PaymentToSalesforceGW opmt;
        account a1 = new account(name='test acct');
        insert a1;
        account a2 = new account(name='another test acct');
        insert a2;
        Contact testCon = new contact(firstname='lily', lastname='testy', accountid=a2.id, email='testing123@bogus.org', GWBase__secondary_email__c = 'testing345@bogus.org');
        insert testCon;     
        Contact testCon2 = new contact(firstname='bob', lastname='testy', accountid=a2.id, gwop__Online_payer_id__c='testing567@bogus.org');
        insert testCon2;        

        // find account payer name match - but don't match contact because name is not there
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.companyName='test acct';
        opmt.companyIsPayer = true;
        opmt.payer.email = 'testing123@bogus.org';
        opmt.fsetPayer();
        system.assert(opmt.companyIsPayer);
        system.assertEquals(a1.id, opmt.payerAccount.Id);
        system.assertEquals(null, opmt.payerContact);
        system.assertEquals(gwop.OnlinePayment.MatchResult.ACCOUNT_MATCH, opmt.payerMatchResult);   
           
        // find account payer name match when there is also a contact
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.opSettings.gwop__Company_Name_Indicates_Org_Payer__c = true;
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.companyName='test acct';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.fsetPayer();
        system.assert(opmt.companyIsPayer);
        system.assertEquals(a1.id, opmt.payerAccount.Id);
        system.assertEquals(testcon.id, opmt.payerContact.Id);
        system.assertEquals(gwop.OnlinePayment.MatchResult.ACCOUNT_MATCH, opmt.payerMatchResult);   
        
        // find contact email match
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.fsetPayer();
        system.assert(!opmt.companyIsPayer);
        system.assertEquals(a2.id, opmt.payerAccount.Id);  // should be contact account, not first test account
        system.assertEquals(testcon.id, opmt.payerContact.Id);
        system.assertEquals(gwop.OnlinePayment.MatchResult.CONTACT_MATCH, opmt.payerMatchResult);   
        
        // find contact 2nd email match
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.email = 'testing345@bogus.org';
        opmt.fsetPayer();
        system.assert(!opmt.companyIsPayer);
        system.assertEquals(a2.id, opmt.payerAccount.Id);  // should be contact account, not first test account
        system.assertEquals(testcon.id, opmt.payerContact.Id);
        system.assertEquals(gwop.OnlinePayment.MatchResult.CONTACT_MATCH, opmt.payerMatchResult);   
        
        // favor the payer id over the name
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.email = 'testing567@bogus.org';
        opmt.fsetPayer();
        system.assertEquals(testcon2.id, opmt.payerContact.Id);
        system.assertEquals(gwop.OnlinePayment.MatchResult.CONTACT_MATCH, opmt.payerMatchResult);   

        // find transaction match - should ignore the contact and account settings
        Opportunity testOpp = New Opportunity (
            Name = 'Test Opp 3',
            accountid = a2.id,
            Amount = 25,
            CloseDate = system.Today().adddays(10),
            StageName = 'Prospecting',
            gwop__Online_Transaction_Id__c = 'X0X0X'
        );
        insert testOpp;
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.companyName='test acct';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.fsetPayer();
        system.assertEquals(a2.id, opmt.payerAccount.Id);
        system.assert(opmt.companyIsPayer);
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
        
        // find no match - create contact and account
        a1.gwop__Online_payer_id__c = null;
        update a1;
        a2.gwop__Online_payer_id__c = null;
        update a2;
        testCon.gwop__Online_payer_id__c = null;
        update testCon;     
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X1X1X';
        opmt.payer.firstName='NOTlily';
        opmt.payer.lastName='NOTtesty';
        opmt.payer.email = 'testing345@bogus.org';
        opmt.fsetPayer();
        system.assert(!opmt.companyIsPayer);
        system.assertEquals(null, opmt.payerAccount); 
        opmt.fsavePayerData();
        system.assertEquals([select id from contact where lastname = 'NOTtesty' and firstname = 'NOTlily' limit 1].id, opmt.contactId);
        system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_CONTACT, opmt.payerMatchResult);
    }
   
    static testMethod void testNewPmtNewAccount () {
        
        // process a payment from a brand new account 
        PaymentToSalesforceGW opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.opSettings.gwop__ITEM_RECORD_TYPES__c = GWBase.ONEN_Constants.OPP_MEMBER_RECTYPE_FORTESTS + ',' + GWBase.ONEN_Constants.OPP_MEMBER_RECTYPE_FORTESTS;
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_MEMBER_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessSinglePayment();
        
        // verify that the opp closed
        opportunity[] o1 = [select id, name, type, accountid, stagename, recordtypeid, amount, closedate 
            from opportunity where account.name = 'testco test industries'];
        system.assertEquals(system.today(), o1[0].closedate);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_WON_NOT_THANKED_STAGE, o1[0].stagename);
        system.assertEquals(12345, o1[0].amount);
        system.assertEquals('Paypal', o1[0].type);
        system.assertEquals(o1[0].id, opmt.opportunityId);
        system.assertEquals(o1[0].accountid, opmt.accountId);
        system.assertEquals(null, opmt.payerContact);
        system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_ACCOUNT, opmt.payerMatchResult); 
        
        // test that the record type was set properly
        system.assertEquals(GWBase.ONEN_Constants.OPP_MEMBER_RECTYPE_FORTESTS, 
            GWBase.GW_RecTypes.getRecordTypeName('Opportunity', o1[0].recordtypeid));
        system.assert(o1[0].name.contains(GWBase.ONEN_Constants.OPP_MEMBER_RECTYPE_FORTESTS), o1[0].name);
    }

    static testMethod void testNewPmtNewContact () {
        
        // process an opp for a brand new contact
        PaymentToSalesforceGW opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtType = gwop.OnlinePayment.PaymentType.CREDITCARD;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessSinglePayment();
        
        // verify that the opp and role are there
        opportunityContactRole[] o1 = [select id, opportunityid, opportunity.stagename, opportunity.accountid, 
            opportunity.name, opportunity.type, opportunity.recordtypeid, opportunity.amount, 
            opportunity.closedate, contactid, contact.homephone from opportunitycontactrole
            where opportunity.gwop__Online_transaction_id__c = 'X0X0X'];
        system.assertEquals(system.today(), o1[0].opportunity.closedate);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_WON_NOT_THANKED_STAGE, o1[0].opportunity.stagename);
        system.assertEquals(12345, o1[0].opportunity.amount);
        system.assertEquals('Credit Card', o1[0].opportunity.type);
        system.assertEquals(null, o1[0].opportunity.accountid);
        system.assertEquals(o1[0].opportunityid, opmt.opportunityId);
        system.assertEquals(o1[0].contactid, opmt.contactId);
        system.assertEquals(o1[0].contactid, opmt.payerContact.Id);
        system.assertEquals(opmt.payer.billingAddress.phone, o1[0].contact.homephone);
        system.assert(o1[0].opportunity.name.contains('lily testy'), o1[0].opportunity.name);
        system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_CONTACT, opmt.payerMatchResult); 

        // test that the record type was set properly
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, 
            GWBase.GW_RecTypes.getRecordTypeName('Opportunity', o1[0].opportunity.recordtypeid));
        system.assert(o1[0].opportunity.name.contains(GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS), o1[0].opportunity.name);
    }

    static testMethod void testNewPmtExistingContact () {
        
        // process a new contact opp
        account a1 = new account(name='test acct');
        insert a1;
        Contact testCon = new contact(firstname='lily', lastname='testy', 
            homephone='do not overwrite', otherstreet='overwrite', email='testing123@bogus.org');
        insert testCon;     
        campaign cmp = new campaign(name='test campaign');
        insert cmp;
        test.startTest();
        
        // create a new payment
        PaymentToSalesforceGW opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.contactOverwrite = new set<string>{'address'};
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payer.billingAddress.street = 'newaddress';
        opmt.payer.billingAddress.city = 'newcity';
        opmt.payment.totalAmount = 12345;
        opmt.payment.custom = string.valueOf(cmp.id);
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessSinglePayment();
        
        // verify that the opp closed
        opportunity[] o1 = [select id, accountid, recordtypeid, stagename, campaignid, closedate 
            from opportunity where  gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.assertEquals(system.today(), o1[0].closedate);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_WON_NOT_THANKED_STAGE, o1[0].stagename);
        system.assertEquals(cmp.id, o1[0].campaignid);
        system.assertEquals(o1[0].id, opmt.opportunityId);
        system.assertEquals(testCon.id, opmt.contactId);
        system.assertEquals(testCon.id, opmt.payerContact.Id);
        contact con1 = [select id, otherstreet, homephone from contact where id=:testcon.id];
        system.assertEquals('newaddress', con1.otherstreet);
        system.assertEquals('do not overwrite', con1.homephone);
        system.assertEquals(gwop.OnlinePayment.MatchResult.CONTACT_MATCH, opmt.payerMatchResult);   

        // process the same opp txn_id again
        // make sure no dupe is created
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.custom = string.valueOf(cmp.id);
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessSinglePayment();
        opportunity[] o2 = [select id from opportunity where gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.assertEquals(1, o2.size());  
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
    }
        
    static testMethod void testExistingPmtExistingContact () {
        
        // process a contact opp that already exists; opp should get marked closed
        account a1 = new account(name='test acct');
        insert a1;
        Contact testCon = new contact(firstname='lily', lastname='testy', email='testing123@bogus.org');
        insert testCon;     
        Opportunity testOpp = New Opportunity (
            Name = 'Test Opp 3',
            accountid = a1.id,
            Amount = 25,
            CloseDate = system.Today().adddays(10),
            StageName = 'Prospecting',
            GWBase__CR_Contact_Id__c = testCon.Id,
            GWBase__CR_Contact_Role__c = 'Individual Donor',
            gwop__Online_Transaction_Id__c = 'X0X0X'
        );
        insert testOpp;
        test.startTest();
        
        // create a payment that matches
        PaymentToSalesforceGW opmt = new PaymentToSalesforceGW();
        system.assert(opmt != null);
        system.assert(opmt.opSettings != null);
        system.assert(PaymentToSalesforceGW.defaultSettings() != null);
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessSinglePayment();
        
        // verify that the opp closed and got its mirror oppPayment record
        opportunity[] o1 = [select id, stagename, amount, closedate from opportunity where id=:testOpp.id];
        system.assertEquals(system.today(), o1[0].closedate);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_WON_NOT_THANKED_STAGE, o1[0].stagename);
        system.assertEquals(12345, o1[0].amount);
        system.assertEquals(testOpp.id, opmt.opportunityId);
        system.assertEquals(testCon.id, opmt.contactId);
        system.assertEquals(testCon.id, opmt.payerContact.Id);
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
    }
    
    static testMethod void testNewPendingPayment () {
        PaymentToSalesforceGW opmt;
        account a1 = new account(name='test acct');
        insert a1;
        Contact testCon = new contact(firstname='lily', lastname='testy', email='testing123@bogus.org');
        insert testCon;     
        test.startTest();

        // process an authorized pmt with option off
        // nothing should happen, because we don't create an opp until we get the money
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.opSettings.gwop__Create_Pending_Opps__c = false;
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.AUTHORIZED;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.fprocessSinglePayment();
        opportunity[] o1 = [select id from opportunity where gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.assertEquals(0, o1.size());  
        
        // process a pending pmt with option on, should create an opp with stage of pending
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.PENDING;
        opmt.payment.txnId = 'X1X1X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.fprocessSinglePayment();
        opportunity[] o2 = [select id, stagename, GWBase__total_unpaid__c from opportunity where gwop__Online_Transaction_Id__c = 'X1X1X'];
        system.assertEquals(opmt.opSettings.gwop__Opp_Stage_for_Pending_Payments__c , o2[0].stagename); 
        system.assertEquals(12345, o2[0].GWBase__total_unpaid__c);  
        system.assertEquals(gwop.OnlinePayment.MatchResult.CONTACT_MATCH, opmt.payerMatchResult);   

        // process the payment notification
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.txnId = 'X1X1X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.fprocessSinglePayment();
        opportunity[] o7 = [select id, stagename, GWBase__total_unpaid__c from opportunity where gwop__Online_Transaction_Id__c = 'X1X1X'];
        // because this closes the last payment for the pledge, GW Base sets the stage
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_WON_NOT_THANKED_STAGE, o7[0].stagename);   
        system.assertEquals(0, o7[0].GWBase__total_unpaid__c);
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   

        // process a failed pmt for one we already have
        // should mark opp as lost
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.FAILED;
        opmt.payment.txnId = 'X1X1X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.fprocessSinglePayment();
        opportunity[] o4 = [select id, stageName from opportunity where gwop__Online_Transaction_Id__c = 'X1X1X'];
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_LOST_STAGE, o4[0].stagename);  
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   

        // process a failed pmt we don't have
        // nothing should happen
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.FAILED;
        opmt.payment.txnId = 'X2X2X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.fprocessSinglePayment();
        opportunity[] o3 = [select id from opportunity where gwop__Online_Transaction_Id__c = 'X2X2X'];
        system.assertEquals(0, o3.size());  
    }

    static testMethod void testSingleAuthThenCapturePayment () {
        PaymentToSalesforceGW opmt;
        account a1 = new account(name='test acct');
        insert a1;
        Contact testCon = new contact(firstname='lily', lastname='testy', email='testing123@bogus.org');
        insert testCon; 
        
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        
        Opportunity testOpp = New Opportunity (
            Name = 'Test Opp 3',
            Amount = 25,
            CloseDate = system.Today(),
            StageName = opmt.opSettings.gwop__Opp_Stage_for_New_Payments__c,
            GWBase__CR_Contact_Id__c = testCon.Id,
            GWBase__CR_Contact_Role__c = 'Individual Donor',
            gwop__Online_Transaction_Id__c = 'X0X0X'
        );
        insert testOpp;
            
        test.startTest();

        // process an authorized pmt with option off
        // nothing should happen, because we don't create an opp until we get the money
        
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.txnId = 'X0X0X';
        opmt.payment.totalAmount = 25;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 25, null, null));
        opmt.fprocessSinglePayment();
        opportunity[] o1 = [select id, stageName from opportunity where gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.assertEquals(opmt.opSettings.gwop__Opp_Stage_for_New_Payments__c, o1[0].StageName);
        system.assertEquals(o1[0].id, opmt.OpportunityId);
    }
    
    static testMethod void testRefund () {
        // process a new contact opp
        account a1 = new account(name='test acct');
        insert a1;
        Contact testCon = new contact(firstname='lily', lastname='testy', 
            homephone='do not overwrite', otherstreet='overwrite', email='testing123@bogus.org');
        insert testCon;     
        test.startTest();
        
        // create a new payment
        PaymentToSalesforceGW opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payer.billingAddress.street = 'newaddress';
        opmt.payer.billingAddress.city = 'newcity';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessSinglePayment();
        opportunity[] o1 = [select id, name, stagename, amount, (select id, gwbase__amount__c, gwbase__online_transaction_id__c from gwbase__Payments__r where GWBase__paid__c = true order by gwbase__amount__c desc) from opportunity where gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.assertEquals(1, o1.size());  
        system.assertEquals(1, o1[0].gwbase__Payments__r.size());  
        system.assertEquals(12345, o1[0].gwbase__Payments__r[0].gwbase__amount__c);  
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_WON_NOT_THANKED_STAGE, o1[0].stagename);  
        system.assertEquals(12345, o1[0].amount);  
        
        // process a refund for that txn_id
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'R0R0R';
        opmt.payment.ParentTxnId = 'X0X0X';
        opmt.payment.totalAmount = null; // = 12345;  // should be okay either way
        opmt.payment.action = gwop.OnlinePayment.PaymentAction.REFUND;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.REVERSED;
        opmt.fprocessSinglePayment();

        // make sure we gave the money back, opp is now $0 and closed lost, there are two payments
        opportunity[] o2 = [select id, name, stagename, amount, (select id, gwbase__amount__c, gwbase__online_transaction_id__c from gwbase__Payments__r where GWBase__isInstallment__c = true and GWBase__paid__c = true order by gwbase__amount__c desc) from opportunity where gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.debug(logginglevel.warn, o2);
        system.debug(logginglevel.warn, o2[0].gwbase__Payments__r);
        system.assertEquals(1, o2.size());  
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
        system.assertEquals(2, o2[0].gwbase__Payments__r.size());  
        system.assertEquals('X0X0X', o2[0].gwbase__Payments__r[0].gwbase__online_transaction_id__c);          
        system.assertEquals(12345, o2[0].gwbase__Payments__r[0].gwbase__amount__c);  
        system.assertEquals('R0R0R', o2[0].gwbase__Payments__r[1].gwbase__online_transaction_id__c);  
        system.assertEquals(-12345, o2[0].gwbase__Payments__r[1].gwbase__amount__c);  
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_LOST_STAGE, o2[0].stagename);  
        system.assertEquals(0, o2[0].amount);  

        // process a refund for the same opp txn_id again
        // make sure no dupe is created
        opmt = new PaymentToSalesforceGW();
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'R0R0R';
        opmt.payment.ParentTxnId = 'X0X0X';
        //opmt.payment.totalAmount = 12345;
        opmt.payment.action = gwop.OnlinePayment.PaymentAction.REFUND;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.REVERSED;
        opmt.fprocessSinglePayment();
        opportunity[] o3 = [select id, stagename, amount, (select id, gwbase__amount__c, gwbase__online_transaction_id__c from gwbase__Payments__r where GWBase__isInstallment__c = true and GWBase__paid__c = true order by gwbase__amount__c desc) from opportunity where gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.assertEquals(1, o3.size());  
        system.assertEquals(2, o3[0].gwbase__Payments__r.size());  
    }  

    static testMethod void testPartialRefund () {
        // process a new contact opp
        account a1 = new account(name='test acct');
        insert a1;
        Contact testCon = new contact(firstname='lily', lastname='testy', 
            homephone='do not overwrite', otherstreet='overwrite', email='testing123@bogus.org');
        insert testCon;     
        test.startTest();
        
        // create a new payment
        PaymentToSalesforceGW opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payer.billingAddress.street = 'newaddress';
        opmt.payer.billingAddress.city = 'newcity';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessSinglePayment();
        opportunity[] o1 = [select id, name, stagename, amount, (select id, gwbase__amount__c, gwbase__online_transaction_id__c from gwbase__Payments__r where GWBase__paid__c = true order by gwbase__amount__c desc) from opportunity where gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.assertEquals(1, o1.size());  
        system.assertEquals(1, o1[0].gwbase__Payments__r.size());  
        system.assertEquals(12345, o1[0].gwbase__Payments__r[0].gwbase__amount__c);  
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_WON_NOT_THANKED_STAGE, o1[0].stagename);  
        system.assertEquals(12345, o1[0].amount);  
        
        // process a refund for that txn_id
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'R0R0R';
        opmt.payment.ParentTxnId = 'X0X0X';
        opmt.payment.totalAmount = 45;          // less than all of it
        opmt.payment.action = gwop.OnlinePayment.PaymentAction.REFUND;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.REVERSED;
        opmt.fprocessSinglePayment();

        // make sure we gave the money back, opp is now $0 and closed lost, there are two payments
        opportunity[] o2 = [select id, name, stagename, amount, (select id, gwbase__amount__c, gwbase__online_transaction_id__c from gwbase__Payments__r where GWBase__isInstallment__c = true and GWBase__paid__c = true order by gwbase__amount__c desc) from opportunity where gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.debug(logginglevel.warn, o2);
        system.debug(logginglevel.warn, o2[0].gwbase__Payments__r);
        system.assertEquals(1, o2.size());  
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
        system.assertEquals(2, o2[0].gwbase__Payments__r.size());  
        system.assertEquals('X0X0X', o2[0].gwbase__Payments__r[0].gwbase__online_transaction_id__c);          
        system.assertEquals(12345, o2[0].gwbase__Payments__r[0].gwbase__amount__c);  
        system.assertEquals('R0R0R', o2[0].gwbase__Payments__r[1].gwbase__online_transaction_id__c);  
        system.assertEquals(-45, o2[0].gwbase__Payments__r[1].gwbase__amount__c);  
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_WON_STAGE, o2[0].stagename);  
        system.assertEquals(12300, o2[0].amount);  
    }

    static testMethod void testRefundRecurring () {

        PaymentToSalesforceGW opmt;
        
        // process a new recurring pmt signup - monthly, not limited
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(-2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtPeriod = gwop.OnlinePayment.RecurringPeriod.MONTH;
        opmt.payment.frequency = 1;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fstartRecurringPayments();
        
        // check for recurring payment profile, and one recurring opp
        opportunity[] o1 = [select id, name, amount, StageName, GWBase__total_unpaid__c, GWBase__recurring_payment_profile__c, 
            GWBase__recurring_payment_profile__r.name, GWBase__recurring_payment_profile__r.GWBase__amount__c from opportunity 
            where GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y' and 
                stagename = :GWBase.ONEN_Constants.OPP_DEFAULT_RECURRING_STAGE];
        system.assertEquals(1,o1.size());
        system.assertEquals(12345, o1[0].amount);   
        system.assertEquals(12345, o1[0].GWBase__total_unpaid__c);  
        system.assertEquals(12345, o1[0].GWBase__recurring_payment_profile__r.GWBase__amount__c);   
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_RECURRING_STAGE, o1[0].StageName);
        system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_ACCOUNT, opmt.payerMatchResult); 
        system.assertEquals('testco test industries ' + system.today().year() + ' Recurring ' + GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, o1[0].name);

        // process payment 
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(-2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessRecurringPayment();
        
        // process a refund for that txn_id
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'R0R0R';
        opmt.payment.ParentTxnId = 'X0X0X';
        opmt.payment.totalAmount = 12345;       // less than all of it
        opmt.payment.action = gwop.OnlinePayment.PaymentAction.REFUND;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.REVERSED;
        
        //opmt.fprocessRecurringPayment(); 
        opmt.fprocessSinglePayment();   // this works too

        // make sure we gave the money back, opp is now $0 and closed lost, there are two payments
        opportunity[] o2 = [select id, name, stagename, amount, (select id, gwbase__amount__c, gwbase__online_transaction_id__c from gwbase__Payments__r where GWBase__isInstallment__c = true and GWBase__paid__c = true order by gwbase__amount__c desc) from opportunity where gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.debug(logginglevel.warn, o2);
        system.debug(logginglevel.warn, o2[0].gwbase__Payments__r);
        system.assertEquals(1, o2.size());  
        system.assertEquals(2, o2[0].gwbase__Payments__r.size());  
        system.assertEquals('X0X0X', o2[0].gwbase__Payments__r[0].gwbase__online_transaction_id__c);          
        system.assertEquals(12345, o2[0].gwbase__Payments__r[0].gwbase__amount__c);  
        system.assertEquals('R0R0R', o2[0].gwbase__Payments__r[1].gwbase__online_transaction_id__c);  
        system.assertEquals(-12345, o2[0].gwbase__Payments__r[1].gwbase__amount__c);  
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_LOST_STAGE, o2[0].stagename);  
        system.assertEquals(0, o2[0].amount);  

        // again, for kicks
        opmt.fprocessRecurringPayment(); 
        opportunity[] o3 = [select id, name, stagename, amount, (select id, gwbase__amount__c, gwbase__online_transaction_id__c from gwbase__Payments__r where GWBase__isInstallment__c = true and GWBase__paid__c = true order by gwbase__amount__c desc) from opportunity where gwop__Online_Transaction_Id__c = 'X0X0X'];
        system.debug(logginglevel.warn, o3);
        system.debug(logginglevel.warn, o3[0].gwbase__Payments__r);
        system.assertEquals(1, o3.size());  
        system.assertEquals(2, o3[0].gwbase__Payments__r.size());  
        system.assertEquals('X0X0X', o3[0].gwbase__Payments__r[0].gwbase__online_transaction_id__c);          
        system.assertEquals(12345, o3[0].gwbase__Payments__r[0].gwbase__amount__c);  
        system.assertEquals('R0R0R', o3[0].gwbase__Payments__r[1].gwbase__online_transaction_id__c);  
        system.assertEquals(-12345, o3[0].gwbase__Payments__r[1].gwbase__amount__c);  
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_LOST_STAGE, o3[0].stagename);  
        system.assertEquals(0, o3[0].amount);  
    }

    static testMethod void testRefundPledgePayment () {

        PaymentToSalesforceGW opmt;
        
        // process a new pledge pmt signup - monthly
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtPeriod = gwop.OnlinePayment.RecurringPeriod.MONTH;
        opmt.payment.frequency = 1;
        opmt.payment.occurrences = 12;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 100;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 100, null, null ));
        opmt.payment.custom = '{"nextstep":"justice"}';
        opmt.fstartRecurringPayments();
        system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_CONTACT, opmt.payerMatchResult); 

        // check for pledge opp with installments.
        opportunity[] o1 = [select id, amount, StageName, GWBase__total_unpaid__c, GWBase__Next_Payment_Due_Date__c,
            GWBase__recurring_payment_profile__c, gwop__Online_pledge_transaction_id__c, GWBase__ContactId__c,
            GWBase__total_paid__c, nextstep from opportunity 
            where gwop__Online_pledge_transaction_id__c = 'Y0Y0Y'];
        system.assertEquals(1200, o1[0].amount);    
        system.assertEquals('justice', o1[0].nextstep);                     
        system.assertEquals(0, o1[0].GWBase__total_paid__c);    
        system.assertEquals(1200, o1[0].GWBase__total_unpaid__c);   
        system.assertEquals(null, o1[0].GWBase__recurring_payment_profile__c);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE, o1[0].StageName);
        system.assertEquals(system.today(), o1[0].GWBase__Next_Payment_Due_Date__c);
        system.assert(o1[0].GWBase__ContactId__c != null);
        
        GWBase__OppPayment__c[] payments1 = [select id, GWBase__Amount__c, GWBase__IsInstallment__c, GWBase__Opp_For_Installment__c,
            GWBase__Online_Transaction_ID__c, GWBase__Paid__c, GWBase__Written_Off__c from GWBase__OppPayment__c
            where GWBase__Opp_For_Installment__c = :o1[0].id and GWBase__IsInstallment__c = true];
        system.assertEquals(12, payments1.size());
        system.assertEquals(false, payments1[0].GWBase__Paid__c);
        system.assertEquals(100, payments1[0].GWBase__Amount__c);
        
        // process first payment
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 100;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 100, null, null ));
        opmt.fprocessRecurringPayment();
        
        // process a refund for that txn_id
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.txnId = 'R0R0R';
        opmt.payment.ParentTxnId = 'X0X0X';
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.totalAmount = null;
        opmt.payment.action = gwop.OnlinePayment.PaymentAction.REFUND;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.REVERSED;

        opmt.fprocessRecurringPayment(); 
        //opmt.fprocessSinglePayment();   // this works too

        // make sure we gave the money back, opp is now $0 and closed lost, there are two payments
        opportunity[] o2 = [select id, name, stagename, amount, (select id, gwbase__amount__c, gwbase__online_transaction_id__c from gwbase__Payments__r where GWBase__isInstallment__c = true and GWBase__paid__c = true order by gwbase__amount__c desc) from opportunity where id= :o1[0].id];
        system.debug(logginglevel.warn, o2);
        system.debug(logginglevel.warn, o2[0].gwbase__Payments__r);
        system.assertEquals(1, o2.size());  
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
        system.assertEquals(2, o2[0].gwbase__Payments__r.size());  
        system.assertEquals('X0X0X', o2[0].gwbase__Payments__r[0].gwbase__online_transaction_id__c);          
        system.assertEquals(100, o2[0].gwbase__Payments__r[0].gwbase__amount__c);  
        system.assertEquals('R0R0R', o2[0].gwbase__Payments__r[1].gwbase__online_transaction_id__c);  
        system.assertEquals(-100, o2[0].gwbase__Payments__r[1].gwbase__amount__c);  
        system.assertEquals(1100, o2[0].amount);  
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE, o2[0].stagename);  
        
    }

    static testMethod void testNewRecurringNewContact () {

        PaymentToSalesforceGW opmt;
        
        // process a new recurring pmt signup - monthly
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtPeriod = gwop.OnlinePayment.RecurringPeriod.MONTH;
        opmt.payment.frequency = 1;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.custom = '{"nextstep":"justice"}';
        opmt.fstartRecurringPayments();
        system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_CONTACT, opmt.payerMatchResult); 

        // check for recurring payment profile and one recurring open opp.
        opportunity[] o1 = [select id, name, amount, StageName, GWBase__total_unpaid__c, GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.name, 
            GWBase__total_paid__c, GWBase__recurring_payment_profile__r.GWBase__amount__c, nextstep from opportunity 
            where GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y'];
        system.assertEquals(12345, o1[0].amount);   
        system.assertEquals('justice', o1[0].nextstep);                     
        system.assertEquals(0, o1[0].GWBase__total_paid__c);    
        system.assertEquals(12345, o1[0].GWBase__total_unpaid__c);  
        system.assertEquals(12345, o1[0].GWBase__recurring_payment_profile__r.GWBase__amount__c);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_RECURRING_STAGE, o1[0].StageName);
        system.assertEquals('lily testy ' + system.today().year() + ' Recurring ' + GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, o1[0].name);
        
        // process first payment
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.fprocessRecurringPayment();
        
        // check that it gets marked paid
        Opportunity[] op1 = [select id, closedate, amount, GWBase__total_unpaid__c, 
            GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.GWBase__transaction_id__c from Opportunity
            where gwop__Online_Transaction_Id__c = 'X0X0X']; 
        system.assertEquals(opmt.recurringPayment.id, op1[0].GWBase__recurring_payment_profile__c); 
        system.assertEquals('Y0Y0Y', op1[0].GWBase__recurring_payment_profile__r.GWBase__transaction_id__c);    
        system.assertEquals(system.today(), op1[0].closedate);  
        system.assertEquals(0, op1[0].GWBase__total_unpaid__c); 
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   

        // do not take this out - you might run into governor limits
        test.startTest();
        
        // process the other payment
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X1X1X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.fprocessRecurringPayment();
        
        // check that it gets marked paid, also that we have two paid opps
        Opportunity[] op2 = [select id, closedate, amount, GWBase__total_unpaid__c, gwop__Online_transaction_id__c,
            GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.GWBase__transaction_id__c from Opportunity
            where GWBase__recurring_payment_profile__r.GWBase__transaction_id__c = 'Y0Y0Y' and isWon = true]; 
        system.debug(op2); 
        system.assertEquals(2, op2.size());
        system.assertEquals('X1X1X', op2[1].gwop__Online_transaction_id__c);
        system.assertEquals(system.today(), op2[1].closedate);
        system.assertEquals(12345, op2[1].amount);
        system.assertEquals(0, op2[1].GWBase__total_unpaid__c); 
        system.assertEquals(opmt.opportunityId, op2[1].id);     
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
        
        // check that both opps have a contact role
        opportunityContactRole[] ocr1 = [select id, opportunityid, opportunity.stagename, opportunity.accountid, 
            opportunity.name, opportunity.type, opportunity.recordtypeid, opportunity.amount, 
            opportunity.closedate, contactid, contact.homephone from opportunitycontactrole
            where opportunity.GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y' order by createddate];
        system.assertEquals(ocr1[0].opportunityid, o1[0].Id);
        system.assertEquals(ocr1[0].contactid, opmt.contactId);
        system.assertEquals(ocr1[1].opportunityid, op2[1].id);
        system.assertEquals(ocr1[1].contactid, opmt.contactId); 
        
        // process the same txn_id again
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X1X1X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.fprocessRecurringPayment();
        
        // nothing should happen - already paid
        Opportunity[] op4 = [select id, closedate, amount, GWBase__total_unpaid__c, gwop__Online_transaction_id__c,
            GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.GWBase__transaction_id__c from Opportunity
            where GWBase__recurring_payment_profile__r.GWBase__transaction_id__c = 'Y0Y0Y' and isWon = true]; 
        system.assertEquals(2, op4.size()); 
        system.assertEquals('X1X1X', op4[1].gwop__Online_transaction_id__c);
        system.assertEquals(12345, op4[1].amount);
        system.assertEquals(0, op4[1].GWBase__total_unpaid__c); 
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   

        // process a new payment, but it is pending
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.PENDING;
        opmt.payment.reasonCode = 'Bad credit, man.';
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X3X3X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.fprocessRecurringPayment();
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
        
        // third opp should not get processed, because it is not paid
        Opportunity[] op5 = [select id, closedate, amount, GWBase__total_unpaid__c, gwop__Online_transaction_id__c,
            GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.GWBase__transaction_id__c from Opportunity
            where gwop__Online_transaction_id__c = 'X3X3X']; 
        system.assertEquals(0, op5.size());
                
        // process cancellation of subscription
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.fcancelRecurringPayments();
        
        // recurring pmt should get closed
        // trigger in GWBase handles logic here of deleting unpaid opps so we won't test for it here
        GWBase__recurring_payment_profile__c[] rp1 = [select id, GWBase__End_Date__c from GWBase__recurring_payment_profile__c 
            where GWBase__Transaction_Id__c = 'Y0Y0Y'];
        system.assertEquals(1, rp1.size()); 
        system.assertEquals(system.today(), rp1[0].GWBase__end_date__c);    
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
    }   
    
    static testMethod void testRecurringNewAccount () {
        PaymentToSalesforceGW opmt;
        
        // process a new recurring pmt signup - monthly, not limited
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(-2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtPeriod = gwop.OnlinePayment.RecurringPeriod.MONTH;
        opmt.payment.frequency = 1;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fstartRecurringPayments();
        
        // check for recurring payment profile, and one recurring opp
        opportunity[] o1 = [select id, name, amount, StageName, GWBase__total_unpaid__c, GWBase__recurring_payment_profile__c, 
            GWBase__recurring_payment_profile__r.name, GWBase__recurring_payment_profile__r.GWBase__amount__c from opportunity 
            where GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y' and 
                stagename = :GWBase.ONEN_Constants.OPP_DEFAULT_RECURRING_STAGE];
        system.assertEquals(1,o1.size());
        system.assertEquals(12345, o1[0].amount);   
        system.assertEquals(12345, o1[0].GWBase__total_unpaid__c);  
        system.assertEquals(12345, o1[0].GWBase__recurring_payment_profile__r.GWBase__amount__c);   
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_RECURRING_STAGE, o1[0].StageName);
        system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_ACCOUNT, opmt.payerMatchResult); 
        system.assertEquals('testco test industries ' + system.today().year() + ' Recurring ' + GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, o1[0].name);

        // process payment 
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(-2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessRecurringPayment();
        
        // check that payment is marked paid
        opportunity[] o2 = [select id, name, amount, GWBase__total_paid__c, GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.name, 
            GWBase__recurring_payment_profile__r.GWBase__amount__c from opportunity 
            where GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y'];
        system.assertEquals(12345, o2[0].GWBase__total_paid__c);    
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
        system.assertEquals('testco test industries ' + system.today().year() + ' Recurring ' + GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, o2[0].name);
        
        // process update of subscription to quarterly
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.opSettings.gwop__ITEM_RECORD_TYPES__c = GWBase.ONEN_Constants.OPP_MEMBER_RECTYPE_FORTESTS + ',' + GWBase.ONEN_Constants.OPP_MEMBER_RECTYPE_FORTESTS;
        opmt.fysm = system.today().addmonths(-2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtPeriod = gwop.OnlinePayment.RecurringPeriod.MONTH;
        opmt.payment.frequency = 3;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fstartRecurringPayments();
        
        // first RP should get closed, opp should get adjusted to amount paid
        Opportunity[] op1 = [select id, closedate, amount, GWBase__total_unpaid__c, gwop__Online_transaction_id__c, GWBase__recurring_payment_profile__r.GWBase__end_date__c,
            GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.GWBase__transaction_id__c from Opportunity
            where GWBase__recurring_payment_profile__c = : o2[0].GWBase__recurring_payment_profile__c and isWon = true]; 
        system.assertEquals(1, op1.size()); 
        system.assertEquals(null, op1[0].GWBase__recurring_payment_profile__r.GWBase__transaction_id__c);
        system.assertEquals(12345, op1[0].amount);  
        system.assertEquals(0, op1[0].GWBase__total_unpaid__c);
        system.assertEquals(system.today(), op1[0].GWBase__recurring_payment_profile__r.GWBase__end_date__c);
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
            
        // second RP should get created with an open opp, shouldn't find opps from old recurring payment because recurring id was cleared
        Opportunity[] op2 = [select id, closedate, amount, GWBase__total_unpaid__c, gwop__Online_transaction_id__c,
            GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.GWBase__transaction_id__c from Opportunity
            where GWBase__recurring_payment_profile__r.GWBase__transaction_id__c = 'Y0Y0Y'];
        system.assertEquals(1, op2.size()); 
        system.assertEquals(12345, op2[0].amount);
        system.assertEquals(12345, op2[0].GWBase__total_unpaid__c);
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
        
        // process cancellation of unpaid subscription
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.fcancelRecurringPayments();
        
        // opp gets marked closed lost, RP closed
        Opportunity[] op3 = [select id, closedate, amount, GWBase__total_unpaid__c, gwop__Online_transaction_id__c, stagename, GWBase__recurring_payment_profile__r.GWBase__end_date__c,
            GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.GWBase__transaction_id__c from Opportunity
            where GWBase__recurring_payment_profile__r.GWBase__transaction_id__c = 'Y0Y0Y'];
        system.assertEquals(1, op3.size()); 
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_LOST_STAGE, op3[0].stagename);
        system.assertEquals(system.today(), op3[0].GWBase__recurring_payment_profile__r.GWBase__end_date__c);
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
    }
        
    static testMethod void testRecurringRandom() {
        PaymentToSalesforceGW opmt;
        
        // process a recurring payment for a recurring pmt ID we have not ever seen
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(-2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessRecurringPayment();
        
        // new monthly RPP should get created, with one paid opp.
        GWBase__recurring_payment_profile__c[] rpp = [select id, GWBase__Start_Date__c from GWBase__recurring_payment_profile__c 
            where GWBase__Transaction_Id__c = 'Y0Y0Y'];
        system.assertEquals(1, rpp.size()); 
        system.assertEquals(system.today(), rpp[0].GWBase__Start_date__c);
        
        opportunity[] o1 = [select id, amount, StageName, GWBase__total_paid__c, GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.name, 
            GWBase__recurring_payment_profile__r.GWBase__amount__c from opportunity 
            where GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y' and isWon = true];
        system.assertEquals(12345, o1[0].amount);   
        system.assertEquals(12345, o1[0].GWBase__recurring_payment_profile__r.GWBase__amount__c);   
        system.assertEquals(12345, o1[0].GWBase__total_paid__c);    
        system.assertEquals(opmt.opSettings.gwop__Opp_Stage_for_Closed_Opps__c, o1[0].StageName);
        system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_ACCOUNT, opmt.payerMatchResult); 
    }   

    static testMethod void testRecurringNoOpenPmts() {
        
        account a1 = new account(name = 'testco test industries', gwop__Online_payer_id__c = 'testing@bogus.org');
        
        PaymentToSalesforceGW opmt;
        
        // start a recurring payment, then write off the payment and try to process a payment afterwards
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtPeriod = gwop.OnlinePayment.RecurringPeriod.YEAR;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.payerId = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payment.totalAmount = 12345;
        opmt.fstartRecurringPayments();

        // verify that the opp is there
        opportunity[] o1 = [select id, name, accountid, stagename, recordtypeid, amount, closedate 
            from opportunity where account.name = 'testco test industries'];
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_RECURRING_STAGE, o1[0].stagename);
        
        // write off the payment
        GWBase__oppPayment__c[] op0 = [select id from GWBase__oppPayment__c where GWBase__opportunity__c = : o1[0].id];
        op0[0].GWBase__written_off__c = true; 
        update op0;

        // mark the opp as lost     
        o1[0].stagename = GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_LOST_STAGE;
        update o1;      

        // process a payment now
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.payerId = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payment.totalAmount = 12345;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessRecurringPayment();
        
        // there should be 3 opps - one closed lost, one all paid, other opp creation handled by trigger and not tested here
        opportunity[] o2 = [select id, name, type, stagename from opportunity 
            where account.name = 'testco test industries' order by createddate];
        system.debug(o2);
        system.assertEquals(3, o2.size());  
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_LOST_STAGE, o2[0].stagename);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_WON_NOT_THANKED_STAGE, o2[1].stagename);
        system.assertEquals('Paypal', o2[0].type);  
        system.assertEquals('Paypal', o2[1].type);  
        
    }

    static testMethod void testRecurringWrongAmount () {
        PaymentToSalesforceGW opmt;
        
        // process a recurring payment with an amount different than the payment record
        // it should be the same as updating the recurring payment - close the old, create the new
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(-2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtPeriod = gwop.OnlinePayment.RecurringPeriod.MONTH;
        opmt.payment.frequency = 1;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fstartRecurringPayments();

        // check that payment is marked paid
        opportunity[] o2 = [select id, amount, GWBase__total_paid__c, GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.name, 
            GWBase__recurring_payment_profile__r.GWBase__amount__c from opportunity 
            where GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y'];
        system.assertEquals(12345, o2[0].amount);   
                
        // process payment for wrong amount 
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(-2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.companyName='testco test industries';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 54321;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 54321, null, null));
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.fprocessRecurringPayment();
        
        // first RP should get closed, opp should be closed lost
        opportunity[] o3 = [select id, amount, stagename, GWBase__recurring_payment_profile__r.GWBase__transaction_id__c,
            GWBase__recurring_payment_profile__r.GWBase__end_date__c from opportunity 
            where GWBase__recurring_payment_profile__c = : o2[0].GWBase__recurring_payment_profile__c];
        system.assertEquals(system.today(), o3[0].GWBase__recurring_payment_profile__r.GWBase__end_date__c);
        system.assertEquals(null, o3[0].GWBase__recurring_payment_profile__r.GWBase__transaction_id__c);
            
        // second RP should get created with an open opp, shouldn't find opps from old recurring payment because recurring id was cleared
        Opportunity[] op2 = [select id, closedate, amount, GWBase__total_unpaid__c, gwop__Online_transaction_id__c, GWBase__total_paid__c,
            GWBase__recurring_payment_profile__c, GWBase__recurring_payment_profile__r.GWBase__transaction_id__c from Opportunity
            where GWBase__recurring_payment_profile__r.GWBase__transaction_id__c = 'Y0Y0Y' and isWon = true];
        system.assertEquals(1, op2.size()); 
        system.assertEquals(54321, op2[0].amount);
        system.assertEquals(54321, op2[0].GWBase__total_paid__c);
        
    }
    
    static testMethod void testJSONparsing () { 
        
        // sample JSON you can send via the custom field
        string js = '{"GWBase__Do_Not_Solicit__c":true, "homephone": "(360) 555-1212",' + 
            ' "contact": {"mailingstate":"NY", "mailingcity":null, ' +
            ' "birthdate":"1999-09-09","bogus_field__c":"nada"}, ' + 
            ' "account":{"billingcity":"Seattle"},' + 
            ' "description": "Created by our nifty payment website."}';

        // try some contact parsing     
        contact con = new contact(lastname = 'smith', mailingcity = 'Portland', birthdate = system.today().addyears(-40));
        account acct = new account(name = 'smithco');
        con = (contact)(PaymentToSalesforceGW.updateSObjectFromJSON('contact', (sobject)con, js));
        system.assertEquals('NY', con.mailingstate);
        system.assertEquals(true, con.GWBase__do_not_solicit__c);
        system.assertEquals('(360) 555-1212', con.homephone);
        system.assertEquals(null, con.mailingcity);
        system.assertEquals(date.newinstance(1999,9,9), con.birthdate);

        // account parsing
        acct = (account)(PaymentToSalesforceGW.updateSObjectFromJSON('account', (sobject)acct, js));
        system.assertEquals('Seattle', acct.billingcity);

        // payment parsing for opp
        opportunity opp = new opportunity(name = 'test opp', closedate = system.today(), stagename = GWBase.ONEN_Constants.OPP_DEFAULT_CLOSED_WON_STAGE);
        opp = (opportunity)(PaymentToSalesforceGW.updateSObjectFromJSON('opportunity', (sobject)opp, js));
        system.assertEquals('Created by our nifty payment website.', opp.description);
    }   

    static testMethod void testMissingInput () {
        PaymentToSalesforceGW opmt = new PaymentToSalesforceGW();
        try {
            opmt.fprocessRecurringPayment();
        } catch (exception e) {
            system.assertEquals('OnlinePaymentException', e.getTypeName());
        }
    }
    
    static testMethod void testNewPledgeNewContact () {

        PaymentToSalesforceGW opmt;
        
        // process a new pledge pmt signup - monthly
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtPeriod = gwop.OnlinePayment.RecurringPeriod.MONTH;
        opmt.payment.frequency = 1;
        opmt.payment.occurrences = 12;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 100;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 100, null, null ));
        opmt.payment.custom = '{"nextstep":"justice"}';
        opmt.fstartRecurringPayments();
        system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_CONTACT, opmt.payerMatchResult); 

        // check for pledge opp with installments.
        opportunity[] o1 = [select id, amount, StageName, GWBase__total_unpaid__c, GWBase__Next_Payment_Due_Date__c,
            GWBase__recurring_payment_profile__c, gwop__Online_pledge_transaction_id__c, GWBase__ContactId__c,
            GWBase__total_paid__c, nextstep from opportunity 
            where gwop__Online_pledge_transaction_id__c = 'Y0Y0Y'];
        system.assertEquals(1200, o1[0].amount);    
        system.assertEquals('justice', o1[0].nextstep);                     
        system.assertEquals(0, o1[0].GWBase__total_paid__c);    
        system.assertEquals(1200, o1[0].GWBase__total_unpaid__c);   
        system.assertEquals(null, o1[0].GWBase__recurring_payment_profile__c);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE, o1[0].StageName);
        system.assertEquals(system.today(), o1[0].GWBase__Next_Payment_Due_Date__c);
        system.assert(o1[0].GWBase__ContactId__c != null);
        
        GWBase__OppPayment__c[] payments1 = [select id, GWBase__Amount__c, GWBase__IsInstallment__c, GWBase__Opp_For_Installment__c,
            GWBase__Online_Transaction_ID__c, GWBase__Paid__c, GWBase__Written_Off__c from GWBase__OppPayment__c
            where GWBase__Opp_For_Installment__c = :o1[0].id and GWBase__IsInstallment__c = true];
        system.assertEquals(12, payments1.size());
        system.assertEquals(false, payments1[0].GWBase__Paid__c);
        system.assertEquals(100, payments1[0].GWBase__Amount__c);
        
        // process first payment
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 100;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 100, null, null ));
        opmt.fprocessRecurringPayment();
        
        // check that it gets marked paid
        Opportunity[] op1 = [select id, closedate, amount, StageName, GWBase__total_paid__c, GWBase__total_unpaid__c, 
            GWBase__recurring_payment_profile__c, GWBase__Next_Payment_Due_Date__c from Opportunity
            where gwop__Online_Pledge_Transaction_Id__c = 'Y0Y0Y']; 
        system.assertEquals(1, op1.size());
        system.assertEquals(100, op1[0].GWBase__total_paid__c); 
        system.assertEquals(1100, op1[0].GWBase__total_unpaid__c);  
        system.assertEquals(null, op1[0].GWBase__recurring_payment_profile__c);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE, op1[0].StageName);
        system.assertEquals(system.today().addmonths(1), op1[0].GWBase__Next_Payment_Due_Date__c);
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   

        payments1 = [select id, GWBase__Amount__c, GWBase__IsInstallment__c, GWBase__Opp_For_Installment__c,
            GWBase__Online_Transaction_ID__c, GWBase__Paid__c, GWBase__Written_Off__c from GWBase__OppPayment__c
            where GWBase__Opp_For_Installment__c = :o1[0].id and GWBase__IsInstallment__c = true];
        system.assertEquals(12, payments1.size());
        system.assertEquals(true, payments1[0].GWBase__Paid__c);
        system.assertEquals(100, payments1[0].GWBase__Amount__c);
        system.assertEquals(opmt.payment.txnId, payments1[0].GWBase__Online_Transaction_ID__c);

        // do not take this out - you might run into governor limits
        test.startTest();
        
        // process another payment
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.startDate = system.today().addmonths(1);
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X1X1X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 100;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 100, null, null ));
        opmt.fprocessRecurringPayment();
        
        // check that it updates correctly
        Opportunity[] op2 = [select id, closedate, amount, StageName, GWBase__total_unpaid__c, GWBase__total_paid__c, gwop__Online_transaction_id__c,
            GWBase__recurring_payment_profile__c, GWBase__Next_Payment_Due_Date__c  from Opportunity
            where gwop__Online_Pledge_Transaction_Id__c = 'Y0Y0Y']; 
        system.assertEquals(1, op2.size());
        system.assertEquals(200, op2[0].GWBase__total_paid__c); 
        system.assertEquals(1000, op2[0].GWBase__total_unpaid__c);  
        system.assertEquals(null, op2[0].GWBase__recurring_payment_profile__c);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE, op2[0].StageName);
        system.assertEquals(system.today().addmonths(2), op2[0].GWBase__Next_Payment_Due_Date__c);
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
        
            
        // process the same txn_id again
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X1X1X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 100;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 100, null, null));
        opmt.fprocessRecurringPayment();
        
        // nothing should happen - already paid
        Opportunity[] op4 = [select id, closedate, amount, StageName, GWBase__total_unpaid__c, GWBase__total_paid__c, gwop__Online_transaction_id__c,
            GWBase__recurring_payment_profile__c, GWBase__Next_Payment_Due_Date__c  from Opportunity
            where gwop__Online_Pledge_Transaction_Id__c = 'Y0Y0Y']; 
        system.assertEquals(1, op4.size());
        system.assertEquals(200, op4[0].GWBase__total_paid__c); 
        system.assertEquals(1000, op4[0].GWBase__total_unpaid__c);  
        system.assertEquals(null, op4[0].GWBase__recurring_payment_profile__c);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE, op4[0].StageName);
        system.assertEquals(system.today().addmonths(2), op4[0].GWBase__Next_Payment_Due_Date__c);
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   

        // process a new payment, but it is pending
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.PENDING;
        opmt.payment.reasonCode = 'Bad credit, man.';
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X3X3X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 12345;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 12345, null, null ));
        opmt.fprocessRecurringPayment();
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   
        
        // should not get processed, because it is not paid
        Opportunity[] op5 = [select id, closedate, amount, StageName, GWBase__total_unpaid__c, GWBase__total_paid__c, gwop__Online_transaction_id__c,
            GWBase__recurring_payment_profile__c, GWBase__Next_Payment_Due_Date__c  from Opportunity
            where gwop__Online_Pledge_Transaction_Id__c = 'Y0Y0Y']; 
        system.assertEquals(1, op5.size());
        system.assertEquals(200, op5[0].GWBase__total_paid__c); 
        system.assertEquals(1000, op5[0].GWBase__total_unpaid__c);  
                
        // process cancellation of subscription
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.fcancelRecurringPayments();
        
        // should close the opp, and update amounts
        Opportunity[] op6 = [select id, closedate, amount, StageName, GWBase__total_unpaid__c, GWBase__total_paid__c, gwop__Online_transaction_id__c,
            GWBase__recurring_payment_profile__c, GWBase__Next_Payment_Due_Date__c  from Opportunity
            where gwop__Online_Pledge_Transaction_Id__c = 'Y0Y0Y']; 
        system.assertEquals(1, op6.size());
        system.assertEquals(200, op6[0].GWBase__total_paid__c);
        system.assertEquals(0, op6[0].GWBase__total_unpaid__c);
        system.assertEquals(200, op6[0].Amount);
        system.assertEquals(opmt.opSettings.gwop__Opp_Stage_for_Closed_Opps__c, op6[0].StageName);
    }   

    static testMethod void testNewPledgeOverpayment () {

        PaymentToSalesforceGW opmt;
        
        // process a new pledge pmt signup - monthly
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtPeriod = gwop.OnlinePayment.RecurringPeriod.MONTH;
        opmt.payment.frequency = 1;
        opmt.payment.occurrences = 2;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 100;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 100, null, null ));
        opmt.payment.custom = '{"nextstep":"justice"}';
        opmt.fstartRecurringPayments();
        system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_CONTACT, opmt.payerMatchResult); 

        // check for pledge opp with installments.
        opportunity[] o1 = [select id, amount, StageName, GWBase__total_unpaid__c, GWBase__Next_Payment_Due_Date__c,
            GWBase__recurring_payment_profile__c, gwop__Online_pledge_transaction_id__c, GWBase__ContactId__c,
            GWBase__total_paid__c, nextstep from opportunity 
            where gwop__Online_pledge_transaction_id__c = 'Y0Y0Y'];
        system.assertEquals(200, o1[0].amount); 
        system.assertEquals('justice', o1[0].nextstep);                     
        system.assertEquals(0, o1[0].GWBase__total_paid__c);    
        system.assertEquals(200, o1[0].GWBase__total_unpaid__c);    
        system.assertEquals(null, o1[0].GWBase__recurring_payment_profile__c);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE, o1[0].StageName);
        system.assertEquals(system.today(), o1[0].GWBase__Next_Payment_Due_Date__c);
        system.assert(o1[0].GWBase__ContactId__c != null);
        
        GWBase__OppPayment__c[] payments1 = [select id, GWBase__Amount__c, GWBase__IsInstallment__c, GWBase__Opp_For_Installment__c,
            GWBase__Online_Transaction_ID__c, GWBase__Paid__c, GWBase__Written_Off__c from GWBase__OppPayment__c
            where GWBase__Opp_For_Installment__c = :o1[0].id and GWBase__IsInstallment__c = true];
        system.assertEquals(2, payments1.size());
        system.assertEquals(false, payments1[0].GWBase__Paid__c);
        system.assertEquals(100, payments1[0].GWBase__Amount__c);
        
        // process first payment
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X0X0X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 100;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 100, null, null ));
        opmt.fprocessRecurringPayment();
        
        // check that it gets marked paid
        Opportunity[] op1 = [select id, closedate, amount, StageName, GWBase__total_paid__c, GWBase__total_unpaid__c, 
            GWBase__recurring_payment_profile__c, GWBase__Next_Payment_Due_Date__c from Opportunity
            where gwop__Online_Pledge_Transaction_Id__c = 'Y0Y0Y']; 
        system.assertEquals(1, op1.size());
        system.assertEquals(100, op1[0].GWBase__total_paid__c); 
        system.assertEquals(100, op1[0].GWBase__total_unpaid__c);   
        system.assertEquals(null, op1[0].GWBase__recurring_payment_profile__c);
        system.assertEquals(GWBase.ONEN_Constants.OPP_DEFAULT_PLEDGED_STAGE, op1[0].StageName);
        system.assertEquals(system.today().addmonths(1), op1[0].GWBase__Next_Payment_Due_Date__c);
        system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult);   

        payments1 = [select id, GWBase__Amount__c, GWBase__IsInstallment__c, GWBase__Opp_For_Installment__c,
            GWBase__Online_Transaction_ID__c, GWBase__Paid__c, GWBase__Written_Off__c from GWBase__OppPayment__c
            where GWBase__Opp_For_Installment__c = :o1[0].id and GWBase__IsInstallment__c = true];
        system.assertEquals(2, payments1.size());
        system.assertEquals(true, payments1[0].GWBase__Paid__c);
        system.assertEquals(100, payments1[0].GWBase__Amount__c);
        system.assertEquals(opmt.payment.txnId, payments1[0].GWBase__Online_Transaction_ID__c);

        // do not take this out - you might run into governor limits
        test.startTest();
        
        // process another payment
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.startDate = system.today().addmonths(1);
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X1X1X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 100;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 100, null, null ));
        opmt.fprocessRecurringPayment();
        
        // check that it updates correctly
        Opportunity[] op2 = [select id, closedate, amount, StageName, GWBase__total_unpaid__c, GWBase__total_paid__c, gwop__Online_transaction_id__c,
            GWBase__recurring_payment_profile__c, GWBase__Next_Payment_Due_Date__c  from Opportunity
            where gwop__Online_Pledge_Transaction_Id__c = 'Y0Y0Y']; 
        system.assertEquals(1, op2.size());
        system.assertEquals(200, op2[0].GWBase__total_paid__c); 
        system.assertEquals(0, op2[0].GWBase__total_unpaid__c); 
        system.assertEquals(null, op2[0].GWBase__recurring_payment_profile__c);
        // DJH: currently, the opp stays open.
        // we've agreed that GWBase will add a trigger to go ahead and close the opp.
        //system.assertEquals(opmt.opSettings.gwop__Opp_Stage_for_Closed_Opps__c, op2[0].StageName);
        //system.assertEquals(null, op2[0].GWBase__Next_Payment_Due_Date__c);
        //system.assertEquals(gwop.OnlinePayment.MatchResult.TRANSACTION_MATCH, opmt.payerMatchResult); 
        
        // send another payment, which should just be handled as a single opp.
        opmt = new PaymentToSalesforceGW();
        opmt.opSettings = PaymentToSalesforceGW.defaultSettings();
        opmt.fysm = system.today().addmonths(2).month();
        opmt.payment.pmtProcessor = gwop.OnlinePayment.Processor.PAYPAL;
        opmt.payment.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
        opmt.payment.startDate = system.today().addmonths(2);
        opmt.payment.recurringTxnId = 'Y0Y0Y';
        opmt.payment.txnId = 'X12X12X';
        opmt.payer.email = 'testing123@bogus.org';
        opmt.payer.firstName='lily';
        opmt.payer.lastName='testy';
        opmt.payer.billingAddress.phone = '(123) 555-1212';
        opmt.payment.totalAmount = 100;
        opmt.payment.itemList = new list<gwop.OnlinePayment.Item>();
        opmt.payment.itemList.add(new gwop.OnlinePayment.Item( GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, '', '', 1, 100, null, null ));
        opmt.fprocessRecurringPayment();    
        
        // should create a new normal opp.
        op2 = [select id, name, closedate, amount, StageName, GWBase__total_unpaid__c, GWBase__total_paid__c, gwop__Online_transaction_id__c,
            GWBase__recurring_payment_profile__c, GWBase__Next_Payment_Due_Date__c  from Opportunity
            where gwop__Online_transaction_id__c = 'X12X12X']; 
        system.assertEquals(1, op2.size());
        system.assertEquals(100, op2[0].GWBase__total_paid__c); 
        system.assertEquals(0, op2[0].GWBase__total_unpaid__c); 
        system.assertEquals(null, op2[0].GWBase__recurring_payment_profile__c);         
        system.assertEquals('lily testy ' + system.today().year() + ' ' + GWBase.ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS, op2[0].name);
    }
    
}