@isTest
public with sharing class OnlinePaymentWebserviceGWTest {


	//--------------------------------------------------------------------------------------------
	// TESTS
	
    static void setCustomSettingDefaults() {
    	delete [select id from gwop__OnlinePaymentSettings__c];
		gwop__OnlinePaymentSettings__c ops = new gwop__OnlinePaymentSettings__c();
		ops.gwop__PaymentToSalesforce_Class_Name__c = 'gwbaseop.PaymentToSalesforceGW';
		insert ops;
    } 
	
	
	static testMethod void testSetPayer() {
		setCustomSettingDefaults();
		gwop.OnlinePaymentWebservice.PaymentInfo p = new gwop.OnlinePaymentWebservice.paymentInfo();
		p.firstname = 'EvanTest';
		p.lastname = 'CallahanTest';
		p.email = 'evantest@groundwiretest.org';
		gwop.OnlinePaymentWebservice.Response resp = gwop.OnlinePaymentWebservice.setPayer( p );
		system.assert(resp.success, 'setPayer returned fail');
		system.assertEquals(gwop.OnlinePayment.MatchResult.NEW_CONTACT, p.payerMatchResult);	
	}

	static testMethod void testSinglePayment() {
		setCustomSettingDefaults();
		insert new Contact(firstName = 'EvanTest', lastName = 'CallahanTest', 
			email = 'evantest@groundwiretest.org');
		
		test.startTest();
		
        // set default setting for matching
        //gwop.opSettings.Dont_Match_Contacts_by_Email__c = false;
                
		gwop.OnlinePaymentWebservice.PaymentInfo p = new gwop.OnlinePaymentWebservice.PaymentInfo();
		p.firstname = 'EvanTest';
		p.lastname = 'CallahanTest';
		p.email = 'evantest@groundwiretest.org';
		p.txnId = 'X0X0X';
		p.totalAmount = 1234;
		
		gwop.OnlinePaymentWebservice.Item i = new gwop.OnlinePaymentWebservice.Item();
		i.name = 'Gift';
		i.amount = 1234;
		p.itemList = new list<gwop.OnlinePaymentWebservice.Item>{ i };
		
		gwop.OnlinePaymentWebservice.Response resp = gwop.OnlinePaymentWebservice.processSinglePayment( p );
		system.assertEquals(gwop.OnlinePayment.MatchResult.CONTACT_MATCH, p.payerMatchResult);	
		system.assert(resp.success, 'processSinglePayment returned fail');
		
		// look for the opp
		GWBase__oppPayment__c[] op0 = [select id, GWBase__paid__c, GWBase__amount__c, GWBase__isinstallment__c from GWBase__oppPayment__c 
			where GWBase__opportunity__r.gwop__Online_Transaction_Id__c = 'X0X0X'];
		system.assertEquals(1, op0.size(), 'no opp with the specified txnid');			
	}

	static testMethod void testRecurring() {
		setCustomSettingDefaults();
		insert new Contact(firstName = 'EvanTest', lastName = 'CallahanTest', 
			email = 'evantest@groundwiretest.org');
		
		test.startTest();
		
		gwop.OnlinePaymentWebservice.PaymentInfo p = new gwop.OnlinePaymentWebservice.PaymentInfo();
		p.firstname = 'EvanTest';
		p.lastname = 'CallahanTest';
		p.email = 'evantest@groundwiretest.org';
		p.txnId = 'X0X0X';
		p.totalAmount = 1234;
		p.pmtPeriod = gwop.OnlinePayment.RecurringPeriod.MONTH;
		p.frequency = 1;
		p.recurringTxnId = 'Y0Y0Y';
		p.phone = '(123) 555-1212';
		
		gwop.OnlinePaymentWebservice.Item i = new gwop.OnlinePaymentWebservice.Item();
		i.name = 'Gift';
		i.amount = 1234;
		p.itemList = new list<gwop.OnlinePaymentWebservice.Item>{ i };
		
		// set up the payments
		gwop.OnlinePaymentWebservice.Response resp = gwop.OnlinePaymentWebservice.startRecurringPayments( p );
		system.assert(resp.success, 'startRecurringPayments returned fail');
		
		string rtid = p.recurringTxnId;
		system.assert(rtid != null, 'No recurring txn id.');

		// look for the payment
		GWBase__oppPayment__c[] op0 = [select id, GWBase__paid__c, GWBase__amount__c, GWBase__isinstallment__c from GWBase__oppPayment__c 
			where GWBase__opportunity__r.GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y' order by GWBase__date__c];
		system.assert(op0.size() > 0, 'no payments found');			
		system.assertEquals(false, op0[0].GWBase__paid__c, 'paid is set when it should not be');			
		
		// log an authorized payment
		p.pmtStatus = gwop.OnlinePayment.PaymentStatus.AUTHORIZED;
		resp = gwop.OnlinePaymentWebservice.processRecurringPayment( p );
		system.assert(resp.success, 'processRecurringPayment returned fail on create/authorize');
		
		// look for the payment
		GWBase__oppPayment__c[] op2 = [select id, GWBase__paid__c, GWBase__amount__c, GWBase__isinstallment__c from GWBase__oppPayment__c 
			where GWBase__opportunity__r.GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y' order by GWBase__date__c];
		system.assertEquals(false, op2[0].GWBase__paid__c, 'paid is set when it should not be');			
		
		// log actual payment success
		p.pmtStatus = gwop.OnlinePayment.PaymentStatus.COMPLETED;
		resp = gwop.OnlinePaymentWebservice.processRecurringPayment( p );
		system.assert(resp.success, 'processRecurringPayment returned fail on fulfilled payment');
		
		// look for the payment
		GWBase__oppPayment__c[] op3 = [select id, GWBase__paid__c, GWBase__amount__c, GWBase__isinstallment__c from GWBase__oppPayment__c 
			where GWBase__opportunity__r.GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y' order by GWBase__date__c];
		system.assertEquals(true, op3[0].GWBase__paid__c, 'paid is not set properly');			
		
		// cancel the rest
		resp = gwop.OnlinePaymentWebservice.cancelRecurringPayments( p );
		system.assert(resp.success, 'cancelRecurringPayments returned fail');
		// look for the payment
		Opportunity[] op4 = [select id from Opportunity 
			where GWBase__recurring_payment_profile__r.GWBase__Transaction_Id__c = 'Y0Y0Y' and isClosed = false];
		system.assertEquals(0, op4.size(), 'unpaid payments exist on canceled subscr');
	}

}