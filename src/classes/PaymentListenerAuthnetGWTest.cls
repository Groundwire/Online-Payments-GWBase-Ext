@isTest
public with sharing class PaymentListenerAuthnetGWTest {


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
        
        PageReference pageRef=Page.gwop__PaymentListenerAuthnet; 
        Test.setCurrentPage(pageRef); 

        // for code coverage, test opening the page with no params 
        gwop.PaymentListenerAuthnet ann = new gwop.PaymentListenerAuthnet();
        //ann.opSettings = gwop.PaymentListenerAuthnet.defaultSettings();
        ann.processNotification();

        // and with a bogus txn type 
        ann = new gwop.PaymentListenerAuthnet();
        //ann.opSettings = gwop.PaymentListenerAuthnet.defaultSettings();
        ApexPages.currentPage().getParameters().put('x_trans_id', 'bogus');
        ApexPages.currentPage().getParameters().put('x_type', 'bogus');
        ann.processNotification();

        // add params for a realistic incoming IPN
        ann = new gwop.PaymentListenerAuthnet();
        //ann.opSettings = gwop.PaymentListenerAuthnet.defaultSettings();
        ApexPages.currentPage().getParameters().put('x_trans_id', '2147490176');
        ApexPages.currentPage().getParameters().put('x_type', 'auth_capture');
        ApexPages.currentPage().getParameters().put('x_response_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_subcode', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_text', 'This transaction has been approved.'); 
        ApexPages.currentPage().getParameters().put('x_description', 'testitem');
        ApexPages.currentPage().getParameters().put('x_auth_code', 'QbJHm4');
        ApexPages.currentPage().getParameters().put('x_first_name', 'Jackie');
        ApexPages.currentPage().getParameters().put('x_last_name', 'Chan');
        ApexPages.currentPage().getParameters().put('x_email', 'donor54321@test.com');
        ApexPages.currentPage().getParameters().put('x_address', '123 4th Ave');
        ApexPages.currentPage().getParameters().put('x_city', 'Seattle');
        ApexPages.currentPage().getParameters().put('x_state', 'WA');
        ApexPages.currentPage().getParameters().put('x_zip', '98101');
        ApexPages.currentPage().getParameters().put('x_country', 'United States');        
        ApexPages.currentPage().getParameters().put('x_amount', '1234.56');
        ApexPages.currentPage().getParameters().put('x_avs_code', 'Y');
        ApexPages.currentPage().getParameters().put('x_cavv_response', '2');
        ApexPages.currentPage().getParameters().put('x_test_request', 'false');
        ApexPages.currentPage().getParameters().put('x_cust_id', '12345678');
        ApexPages.currentPage().getParameters().put('x_company', 'Kung Fu Inc.');
        ApexPages.currentPage().getParameters().put('x_tax', '1');
        ApexPages.currentPage().getParameters().put('x_freight', '1');
        ApexPages.currentPage().getParameters().put('x_po_num', '987654');
        ApexPages.currentPage().getParameters().put('x_MD5_Hash', 'a045bf296af1c3163ccf9f31c3b3012e');
        
        // process it
        ann.processNotification();

        // verify that it was logged         
        gwop__payment_notification__c ipn;
        ipn = [select name, gwop__payment_amount__c, gwop__isProcessed__c from gwop__payment_notification__c where 
            gwop__payer_email__c = 'donor54321@test.com' limit 1];
        system.assertEquals('Authnet Silent Post - auth_capture from donor54321@test.com', ipn.name);
        system.assertEquals(1234.56, ipn.gwop__payment_amount__c);
        system.debug('DJH: ipn is:');
        system.debug(ipn);
        system.assertEquals(true, ipn.gwop__isprocessed__c);

        // this time it is a subscription
        ann = new gwop.PaymentListenerAuthnet();
        //ann.opSettings = gwop.PaymentListenerAuthnet.defaultSettings();
        ApexPages.currentPage().getParameters().put('x_trans_id', '9383726293');
        ApexPages.currentPage().getParameters().put('x_type', 'auth_capture');
        ApexPages.currentPage().getParameters().put('x_response_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_subcode', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_text', 'This transaction has been approved.'); 
        ApexPages.currentPage().getParameters().put('x_description', 'testitem');
        ApexPages.currentPage().getParameters().put('x_auth_code', 'QbJHm4');
        ApexPages.currentPage().getParameters().put('x_first_name', 'Jackie');
        ApexPages.currentPage().getParameters().put('x_last_name', 'Chan');
        ApexPages.currentPage().getParameters().put('x_email', 'donor321@test.com');
        ApexPages.currentPage().getParameters().put('x_address', '123 4th Ave');
        ApexPages.currentPage().getParameters().put('x_city', 'Seattle');
        ApexPages.currentPage().getParameters().put('x_state', 'WA');
        ApexPages.currentPage().getParameters().put('x_zip', '98101');
        ApexPages.currentPage().getParameters().put('x_country', 'United States');        
        ApexPages.currentPage().getParameters().put('x_amount', '0.5');
        ApexPages.currentPage().getParameters().put('x_avs_code', 'Y');
        ApexPages.currentPage().getParameters().put('x_cavv_response', '2');
        ApexPages.currentPage().getParameters().put('x_test_request', 'false');
        ApexPages.currentPage().getParameters().put('x_cust_id', '12345678');
        ApexPages.currentPage().getParameters().put('x_tax', '1');
        ApexPages.currentPage().getParameters().put('x_freight', '1');
        ApexPages.currentPage().getParameters().put('x_po_num', '987654');
        ApexPages.currentPage().getParameters().put('x_MD5_Hash', '58d30bfb8a3d3c835813d7c4e21275fd');
        ApexPages.currentPage().getParameters().put('x_subscription_id', '629383746');
        ApexPages.currentPage().getParameters().put('x_subscription_paynum', '1');
        ann.processNotification();

        // verify that it was logged         
        ipn = [select name, gwop__payment_amount__c from gwop__payment_notification__c where 
            gwop__payer_email__c = 'donor321@test.com' limit 1];
        system.assertEquals('Authnet Silent Post - auth_capture from donor321@test.com', ipn.name);
        system.assertEquals(0.5, ipn.gwop__payment_amount__c);

        // now a refund
        ann = new gwop.PaymentListenerAuthnet();
        //ann.opSettings = gwop.PaymentListenerAuthnet.defaultSettings();
        ApexPages.currentPage().getParameters().put('x_trans_id', '9383726293');
        ApexPages.currentPage().getParameters().put('x_type', 'credit');
        ApexPages.currentPage().getParameters().put('x_response_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_subcode', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_code', '33');
        ApexPages.currentPage().getParameters().put('x_response_reason_text', 'Money baby.'); 
        ApexPages.currentPage().getParameters().put('x_description', 'refund please');
        ApexPages.currentPage().getParameters().put('x_auth_code', 'QbJHm4');
        ApexPages.currentPage().getParameters().put('x_first_name', 'Jackie');
        ApexPages.currentPage().getParameters().put('x_last_name', 'Chan');
        ApexPages.currentPage().getParameters().put('x_email', 'donor321@test.com');
        ApexPages.currentPage().getParameters().put('x_address', '123 4th Ave');
        ApexPages.currentPage().getParameters().put('x_city', 'Seattle');
        ApexPages.currentPage().getParameters().put('x_state', 'WA');
        ApexPages.currentPage().getParameters().put('x_zip', '98101');
        ApexPages.currentPage().getParameters().put('x_country', 'United States');        
        ApexPages.currentPage().getParameters().put('x_amount', '0.5');
        ApexPages.currentPage().getParameters().put('x_avs_code', 'Y');
        ApexPages.currentPage().getParameters().put('x_cavv_response', '2');
        ApexPages.currentPage().getParameters().put('x_test_request', 'false');
        ApexPages.currentPage().getParameters().put('x_cust_id', '12345678');
        ApexPages.currentPage().getParameters().put('x_tax', '1');
        ApexPages.currentPage().getParameters().put('x_freight', '1');
        ApexPages.currentPage().getParameters().put('x_MD5_Hash', '58d30bfb8a3d3c835813d7c4e21275fd');
        ApexPages.currentPage().getParameters().put('x_subscription_id', '629383746');
        ApexPages.currentPage().getParameters().put('x_subscription_paynum', '1');
        ann.processNotification();
        
        ipn = [select name, gwop__payment_amount__c from gwop__payment_notification__c where 
            gwop__item_name__c = 'refund please' limit 1];
        system.assertEquals('Authnet Silent Post - credit from donor321@test.com', ipn.name);
        system.assertEquals(0.5, ipn.gwop__payment_amount__c);        

        // bad hash
        ann = new gwop.PaymentListenerAuthnet();
        //ann.opSettings = gwop.PaymentListenerAuthnet.defaultSettings();
        ApexPages.currentPage().getParameters().put('x_trans_id', '242424234242');
        ApexPages.currentPage().getParameters().put('x_type', 'auth_capture');
        ApexPages.currentPage().getParameters().put('x_response_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_subcode', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_text', 'This transaction has been approved.'); 
        ApexPages.currentPage().getParameters().put('x_description', 'testitem');
        ApexPages.currentPage().getParameters().put('x_auth_code', 'QbJHm4');
        ApexPages.currentPage().getParameters().put('x_email', null);
        ApexPages.currentPage().getParameters().put('x_first_name', 'Jackie');
        ApexPages.currentPage().getParameters().put('x_last_name', 'Chan');
        ApexPages.currentPage().getParameters().put('x_amount', '4321.56');
        ApexPages.currentPage().getParameters().put('x_avs_code', 'Y');
        ApexPages.currentPage().getParameters().put('x_cavv_response', '2');
        ApexPages.currentPage().getParameters().put('x_test_request', 'false');
        ApexPages.currentPage().getParameters().put('x_cust_id', '666');
        ApexPages.currentPage().getParameters().put('x_company', 'Kung Fu Inc.');
        ApexPages.currentPage().getParameters().put('x_tax', '1');
        ApexPages.currentPage().getParameters().put('x_freight', '1');
        ApexPages.currentPage().getParameters().put('x_po_num', '987654');
        ApexPages.currentPage().getParameters().put('x_MD5_Hash', 'a045bf296af1c3163ccf9f31c3b3012e');
        ann.processNotification();
        
        ipn = [select name, gwop__isprocessed__c from gwop__payment_notification__c where 
            gwop__transaction_id__c = '242424234242' limit 1];
        system.assertEquals('Authnet Silent Post - auth_capture', ipn.name);
        system.assertEquals(false, ipn.gwop__isprocessed__c);
    }
    
    static testMethod void testAuthOnlyThenCapture () {
        setCustomSettingDefaults();
        
        PageReference pageRef=Page.gwop__PaymentListenerAuthnet; 
        Test.setCurrentPage(pageRef); 
        
        // for code coverage, test opening the page with no params 
        gwop.PaymentListenerAuthnet ann = new gwop.PaymentListenerAuthnet();
        //ann.opSettings = gwop.PaymentListenerAuthnet.defaultSettings();
        ann.processNotification();

        // and with a bogus txn type 
        ann = new gwop.PaymentListenerAuthnet();
        //ann.opSettings = gwop.PaymentListenerAuthnet.defaultSettings();
        ApexPages.currentPage().getParameters().put('x_trans_id', 'bogus');
        ApexPages.currentPage().getParameters().put('x_type', 'bogus');
        ann.processNotification();

        // add params for a realistic incoming IPN
        ann = new gwop.PaymentListenerAuthnet();
        //ann.opSettings = gwop.PaymentListenerAuthnet.defaultSettings();
        ApexPages.currentPage().getParameters().put('x_trans_id', '2147490176');
        ApexPages.currentPage().getParameters().put('x_type', 'auth_only');
        ApexPages.currentPage().getParameters().put('x_response_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_subcode', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_text', 'This transaction has been approved.'); 
        ApexPages.currentPage().getParameters().put('x_description', 'testitem');
        ApexPages.currentPage().getParameters().put('x_auth_code', 'QbJHm4');
        ApexPages.currentPage().getParameters().put('x_first_name', 'Jackie');
        ApexPages.currentPage().getParameters().put('x_last_name', 'Chan');
        ApexPages.currentPage().getParameters().put('x_email', 'donor54321@test.com');
        ApexPages.currentPage().getParameters().put('x_address', '123 4th Ave');
        ApexPages.currentPage().getParameters().put('x_city', 'Seattle');
        ApexPages.currentPage().getParameters().put('x_state', 'WA');
        ApexPages.currentPage().getParameters().put('x_zip', '98101');
        ApexPages.currentPage().getParameters().put('x_country', 'United States');        
        ApexPages.currentPage().getParameters().put('x_amount', '1234.56');
        ApexPages.currentPage().getParameters().put('x_avs_code', 'Y');
        ApexPages.currentPage().getParameters().put('x_cavv_response', '2');
        ApexPages.currentPage().getParameters().put('x_test_request', 'false');
        ApexPages.currentPage().getParameters().put('x_cust_id', '12345678');
        ApexPages.currentPage().getParameters().put('x_company', 'Kung Fu Inc.');
        ApexPages.currentPage().getParameters().put('x_tax', '1');
        ApexPages.currentPage().getParameters().put('x_freight', '1');
        ApexPages.currentPage().getParameters().put('x_po_num', '987654');
        ApexPages.currentPage().getParameters().put('x_MD5_Hash', 'a045bf296af1c3163ccf9f31c3b3012e');
        
        // process it
        ann.processNotification();

        // verify that it was logged but not marked processed        
        gwop__payment_notification__c ipn;
        ipn = [select name, gwop__payment_amount__c, gwop__isProcessed__c from gwop__payment_notification__c where 
            gwop__payer_email__c = 'donor54321@test.com' limit 1];
        system.assertEquals('Authnet Silent Post - auth_only from donor54321@test.com', ipn.name);
        system.assertEquals(1234.56, ipn.gwop__payment_amount__c);
        system.assertEquals(false, ipn.gwop__IsProcessed__c); 

        // this time it is prior auth capture, with limited contact data
        ann = new gwop.PaymentListenerAuthnet();
        //ann.opSettings = gwop.PaymentListenerAuthnet.defaultSettings();
        ApexPages.currentPage().getParameters().put('x_trans_id', '2147490176');
        ApexPages.currentPage().getParameters().put('x_type', 'prior_auth_capture');
        ApexPages.currentPage().getParameters().put('x_zip', '98101');
        ApexPages.currentPage().getParameters().put('x_response_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_subcode', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_code', '1');
        ApexPages.currentPage().getParameters().put('x_response_reason_text', 'This transaction has been approved.'); 
        ApexPages.currentPage().getParameters().put('x_description', 'testitem');
        ApexPages.currentPage().getParameters().put('x_auth_code', 'QbJHm4');
        ApexPages.currentPage().getParameters().put('x_country', 'United States');        
        ApexPages.currentPage().getParameters().put('x_amount', '1234.56');
        ApexPages.currentPage().getParameters().put('x_avs_code', 'P');
        ApexPages.currentPage().getParameters().put('x_cavv_response', '2');
        ApexPages.currentPage().getParameters().put('x_test_request', 'false');
        ApexPages.currentPage().getParameters().put('x_tax', '1');
        ApexPages.currentPage().getParameters().put('x_freight', '1');
        ApexPages.currentPage().getParameters().put('x_po_num', '987654');
        ApexPages.currentPage().getParameters().put('x_MD5_Hash', 'a045bf296af1c3163ccf9f31c3b3012e');
        ann.processNotification();

        // assume that this code was scheduled and ran as expected
        Test.startTest();
        gwop.OnlinePaymentAuthnetAsync batch = new gwop.OnlinePaymentAuthnetAsync(
            'SELECT id, gwop__Transaction_Type__c, gwop__Transaction_Id__c, gwop__Recurring_Transaction_Id__c, gwop__Item_Name__c, gwop__Payer_Email__c, ' +
                ' gwop__Payer_ID__c, gwop__Payment_Amount__c, gwop__Payment_Status__c, gwop__Request__c from gwop__Payment_Notification__c ' + 
                ' WHERE gwop__IsProcessed__c = false AND gwop__IsTest__c = false AND gwop__Transaction_Id__c = \'2147490176\'' +
                ' ORDER BY gwop__transaction_type__c DESC LIMIT 10'       
        );
        id batchinstanceid = database.executeBatch (batch, 10);
        test.stopTest();

        // verify that it was logged
        ipn = [select name, gwop__IsProcessed__c, gwop__Opportunity__c, gwop__opportunity__r.GWBase__total_unpaid__c from gwop__payment_notification__c where 
            gwop__Transaction_Id__c = '2147490176' AND gwop__Transaction_Type__c = 'prior_auth_capture' limit 1];
        system.assertEquals(true, ipn.gwop__IsProcessed__c);
        system.assert(ipn.gwop__Opportunity__c != null);
        
        // verify that installment was marked paid
        system.assertEquals(0, ipn.gwop__opportunity__r.GWBase__total_unpaid__c);
    }
 
}