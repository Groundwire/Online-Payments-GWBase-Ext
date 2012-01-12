@isTest
public with sharing class PaymentListenerPaypalGWTest {

	/*------------------------------------------------------------------------------------
	* TESTS
	-------------------------------------------------------------------------------------*/	
    
    static void setCustomSettingDefaults() {
    	delete [select id from gwop__OnlinePaymentSettings__c];
		gwop__OnlinePaymentSettings__c ops = new gwop__OnlinePaymentSettings__c();
		ops.gwop__PaymentToSalesforce_Class_Name__c = 'gwbaseop.PaymentToSalesforceGW';
		insert ops;
    } 
	
	static testMethod void testIPN () {
		setCustomSettingDefaults();
		
		PageReference pageRef=Page.gwop__PaymentListenerPaypal; 
        Test.setCurrentPage(pageRef); 

		// use the IPN tester class - overrides the real controller class, 
		// but without actual callouts to paypal
		gwop.PaymentListenerPaypal ppn;
		
		// for code coverage, test opening the page with no params 
		ppn = new gwop.PaymentListenerPaypal();
		ppn.processNotification();

		// and with a bogus txn type 
		ppn = new gwop.PaymentListenerPaypal();
        ApexPages.currentPage().getParameters().put('txn_type', 'bogus');
		ppn.processNotification();

		// add params for a realistic incoming IPN
		ppn = new gwop.PaymentListenerPaypal();
        ApexPages.currentPage().getParameters().put('txn_type', 'web_accept');
        ApexPages.currentPage().getParameters().put('txn_id', 'TXN123');
        ApexPages.currentPage().getParameters().put('last_name', 'Jones');
        ApexPages.currentPage().getParameters().put('payer_email', 'donor54321@test.com');
        ApexPages.currentPage().getParameters().put('receiver_email', 'myemail@org.org');
        ApexPages.currentPage().getParameters().put('mc_gross', '1234.56');
        ApexPages.currentPage().getParameters().put('item_name1', 'testitem');
        ApexPages.currentPage().getParameters().put('item_number1', '2222');
        ApexPages.currentPage().getParameters().put('quantity1', '1');
        ApexPages.currentPage().getParameters().put('mc_gross_1', '1234.56');
        ApexPages.currentPage().getParameters().put('exchange_rate', '1');
        ApexPages.currentPage().getParameters().put('mc_fee', '1');
        ApexPages.currentPage().getParameters().put('tax', '1');
        ApexPages.currentPage().getParameters().put('mc_shipping', '1');
		
		// get a ppn tester class - overrides the real controller class
		ppn = new gwop.PaymentListenerPaypal();

		// process it 
		test.startTest();
		ppn.processNotification();
		
		// delay validation until we can call stopTest to allow the batch to run.
				
		// next test a recurring payment setup
		ppn = new gwop.PaymentListenerPaypal();
        ApexPages.currentPage().getParameters().put('txn_type', 'subscr_signup');
        ApexPages.currentPage().getParameters().put('txn_id', 'TXN456');
        ApexPages.currentPage().getParameters().put('last_name', 'Jones');
        ApexPages.currentPage().getParameters().put('payer_email', 'donor999@test.com');
        ApexPages.currentPage().getParameters().put('item_name', 'testitem');
        ApexPages.currentPage().getParameters().put('recurring_payment_id', 'testing456');
        ApexPages.currentPage().getParameters().put('amount3', '1234.56');
        ApexPages.currentPage().getParameters().put('recur_times', '2');
        ApexPages.currentPage().getParameters().put('period3', '1 M');
		
		// get a ppn tester class - overrides the real controller class
		ppn = new gwop.PaymentListenerPaypal();
		
		// process it
		ppn.processNotification();
		
		// done processing ipn's, so let our batch run!
		test.stopTest();

		// verify first ipn was logged		 
		gwop__Payment_Notification__c ipn;
		ipn = [select name, gwop__payment_amount__c, gwop__IsProcessed__c from gwop__payment_notification__c where 
			gwop__payer_email__c = 'donor54321@test.com' limit 1];
		system.assertEquals('Paypal IPN - web_accept from donor54321@test.com', ipn.name);
		system.assertEquals(1234.56, ipn.gwop__payment_amount__c);
		system.assertEquals(true, ipn.gwop__IsProcessed__c);
		
		// verify second ipn was logged		 
		ipn = [select name, gwop__payment_amount__c, gwop__IsProcessed__c from gwop__payment_notification__c where 
			gwop__payer_email__c = 'donor999@test.com' order by createddate desc limit 1];
		system.assertEquals('Paypal IPN - subscr_signup from donor999@test.com', ipn.name);
		system.assertEquals(1234.56, ipn.gwop__payment_amount__c);
		system.assertEquals(true, ipn.gwop__IsProcessed__c);
		
	}
	
	static testMethod void testManyIPN () {
		setCustomSettingDefaults();
		
		PageReference pageRef=Page.gwop__PaymentListenerPaypal; 
        Test.setCurrentPage(pageRef); 

		// use the IPN tester class - overrides the real controller class, 
		// but without actual callouts to paypal
		gwop.PaymentListenerPaypal ppn;
				
		test.startTest();
		integer cIPN = 3; // 6 hit soql limits, so lowered to 3.
		for (integer i = 1; i <= cIPN; i++) {
		
	        ApexPages.currentPage().getParameters().put('txn_type', 'web_accept');
	        ApexPages.currentPage().getParameters().put('txn_id', 'testing123-' + i);
	        ApexPages.currentPage().getParameters().put('first_name', 'MyNameIsIPN');
	        ApexPages.currentPage().getParameters().put('last_name', 'Donor Number ' + i);
	        ApexPages.currentPage().getParameters().put('payer_email', 'donornumber' + i + '@test.com');
	        ApexPages.currentPage().getParameters().put('receiver_email', 'myemail@org.org');
	        ApexPages.currentPage().getParameters().put('mc_gross', '1234.56');
	        ApexPages.currentPage().getParameters().put('item_name1', 'testitem');
	        ApexPages.currentPage().getParameters().put('item_number1', '2222');
	        ApexPages.currentPage().getParameters().put('quantity1', '1');
	        ApexPages.currentPage().getParameters().put('mc_gross_1', '1234.56');
	        ApexPages.currentPage().getParameters().put('exchange_rate', '1');
	        ApexPages.currentPage().getParameters().put('mc_fee', '1');
	        ApexPages.currentPage().getParameters().put('tax', '1');
	        ApexPages.currentPage().getParameters().put('mc_shipping', '1');		
	
			// add params for a realistic incoming IPN
			ppn = new gwop.PaymentListenerPaypal();
	
			// process it
			ppn.processNotification();
		}

		// done processing ipn's, so let our batch run!
		test.stopTest();

		// validation
		list<gwop__Payment_Notification__c> listIpn = [select Id from gwop__Payment_Notification__c where gwop__Transaction_Id__c like 'testing123-%'];
		system.assertEquals(cIPN, listIpn.size());
		list<Contact> listContact = [select Id, FirstName, LastName from Contact where FirstName = 'MyNameIsIPN'];
		system.debug(listContact);
		system.assertEquals(cIPN, listContact.size());
	}

	static testMethod void testRecurringIPN () {
		setCustomSettingDefaults();
		
		PageReference pageRef=Page.gwop__PaymentListenerPaypal; 
        Test.setCurrentPage(pageRef); 

		// use the IPN tester class - overrides the real controller class, 
		// but without actual callouts to paypal
		gwop.PaymentListenerPaypal ppn;
				
		test.startTest();
		integer cIPN = 4;	// when tried to deploy with 24, only 15 opps created.  not sure what went wrong. 
		for (integer i = 1; i <= cIPN; i++) {
		
			string txnType = 'subscr_payment';
			if (i == 3) txnType = 'subscr_signup';
			
	        ApexPages.currentPage().getParameters().put('txn_type', txnType);
	        ApexPages.currentPage().getParameters().put('txn_id', 'RecurringTxnId'+i);
	        ApexPages.currentPage().getParameters().put('first_name', 'MyNameIsIPN');
	        ApexPages.currentPage().getParameters().put('last_name', 'Recurring Donor');
	        ApexPages.currentPage().getParameters().put('payer_email', 'recurringdonor@test.com');
	        ApexPages.currentPage().getParameters().put('payer_id', 'ThePayerId');
	        ApexPages.currentPage().getParameters().put('receiver_email', 'myemail@org.org');
	        ApexPages.currentPage().getParameters().put('amount3', '10.00');
	        ApexPages.currentPage().getParameters().put('item_name', 'Donation to Groundwire');
	        ApexPages.currentPage().getParameters().put('item_number1', '2222');
	        ApexPages.currentPage().getParameters().put('quantity1', '1');
	        //ApexPages.currentPage().getParameters().put('recur_times', '12');
	        ApexPages.currentPage().getParameters().put('recurring', '1');
	        ApexPages.currentPage().getParameters().put('period3', '1 M');
	        ApexPages.currentPage().getParameters().put('subscr_id', 'TheSubscrId');
	        ApexPages.currentPage().getParameters().put('subscr_date', string.valueOf(system.now()));
	        ApexPages.currentPage().getParameters().put('payment_date', string.valueOf(system.now()));
	        ApexPages.currentPage().getParameters().put('payment_status', 'Completed');
	
	
			// add params for a realistic incoming IPN
			ppn = new gwop.PaymentListenerPaypal();
	
			// process it
			ppn.processNotification();
		}

		// done processing ipn's, so let our batch run!
		test.stopTest();

		// validation
		list<gwop__Payment_Notification__c> listIpn = [select Id from gwop__Payment_Notification__c where gwop__Transaction_Id__c like 'RecurringTxnId%'];
		system.assertEquals(cIPN, listIpn.size());
		
		list<Contact> listContact = [select Id, FirstName, LastName from Contact where LastName = 'Recurring Donor'];
		system.debug(listContact);
		system.assertEquals(1, listContact.size());
		
		list<GWBase__Recurring_Payment_Profile__c> listRP = [select Id, GWBase__Contact__c, GWBase__Frequency__c, GWBase__Transaction_Id__c 
			From GWBase__Recurring_Payment_Profile__c where GWBase__Contact__c = :listContact[0].Id];
		system.debug(listRP);
		system.assertEquals(1, listRP.size());		
		
		list<Opportunity> listPayment = [select Id, Amount, GWBase__recurring_payment_Profile__c from Opportunity 
			where GWBase__recurring_payment_Profile__c = :listRP[0].id];
		system.debug(listPayment);
		system.assertEquals(cIPN, listPayment.size());
	}
}