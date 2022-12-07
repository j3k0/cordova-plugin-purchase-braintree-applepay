//
//  BraintreeApplePayPlugin.m
//

#import <objc/runtime.h>
#import <BraintreeDropIn/BraintreeDropIn.h>
#import "BraintreePlugin.h"
#import <Foundation/Foundation.h>
#import <Cordova/CDV.h>

/*
 * Constants
 */

#define VERBOSITY_DEBUG 4
#define VERBOSITY_INFO 3
#define VERBOSITY_WARN 2
#define VERBOSITY_ERROR 1

@interface BraintreeApplePayPlugin : CDVPlugin <PKPaymentAuthorizationViewControllerDelegate>

- (void) setLogger:(CDVInvokedUrlCommand *)command;
- (void) setVerbosity:(CDVInvokedUrlCommand*)command;

/// Return a boolean, true if ApplePay is supported.
- (void) isApplePaySupported:(CDVInvokedUrlCommand*)command;
- (void) presentDropInPaymentUI:(CDVInvokedUrlCommand *)command;

- (void) initialize:(CDVInvokedUrlCommand*)command;

@end

@implementation BraintreeApplePayPlugin

static CDVInvokedUrlCommand *dropInUICommand;
static BOOL applePaySuccess;
//NSString * applePayMerchantID;
//NSString * currencyCode;
//NSString * countryCode;
//NSArray<PKPaymentNetwork> * supportedNetworks;
//NSString * threeDResultNonce;

/// Callback called to send native logs to javascript
static NSString *loggerCallback = nil;

/// Level of verbosity for the plugin
static long verbosityLevel = VERBOSITY_INFO;

/// Prefix used for logs from the braintree plugin
static const NSString *LOG_PREFIX = @"CordovaPlugin.Braintree";

#pragma mark - Cordova commands

/// Change the plugin verbosirty level
- (void) setVerbosity:(CDVInvokedUrlCommand*)command {
    NSNumber *value = [command argumentAtIndex:0
                                   withDefault:[NSNumber numberWithInt: VERBOSITY_INFO]
                                      andClass:[NSNumber class]];
    verbosityLevel = value.integerValue;
    [self debug:[NSString stringWithFormat:@"[setVerbosity] %zd", verbosityLevel]];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

/// Set a callback that will display native logs in javascript
- (void) setLogger:(CDVInvokedUrlCommand*)command {
    loggerCallback = command.callbackId;
    [self debug:[NSString stringWithFormat:@"[setLogger] %@", loggerCallback]];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_NO_RESULT];
    pluginResult.keepCallback = [NSNumber  numberWithBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)initialize:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
}

// Returns whether the user can make payments.
//
// returns the value from PassKit (Apple Pay and Wallet): PKPaymentAuthorizationViewController.canMakePayments
- (void) isApplePaySupported:(CDVInvokedUrlCommand*)command {
    BOOL message = [self isApplePaySupported];
    CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:message];
    [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
}

- (BOOL) isApplePaySupported {
    return ((PKPaymentAuthorizationViewController.canMakePayments) && ([PKPaymentAuthorizationViewController canMakePaymentsUsingNetworks:@[PKPaymentNetworkVisa, PKPaymentNetworkMasterCard, PKPaymentNetworkAmex, PKPaymentNetworkDiscover]]));
}

#pragma mark - Present UI

//
// PassKit
// -------
//
// Present the payment UI.
//
- (void)presentDropInPaymentUI:(CDVInvokedUrlCommand*)command {

    BTAPIClient *apiClient = [BraintreePlugin getClient];
    // Ensure the client has been initialized.
    if (!apiClient) {
        CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"The Braintree client has not be initialized."];
        [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
        return;
    }
        
    if (![self isApplePaySupported]) {
        CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"ApplePay cannot be used."];
        [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
        return;
    }

    // Ensure we have the correct number of arguments.
    if ([command.arguments count] < 1) {
        CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Request argument is required."];
        [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
        return;
    }
    
    NSDictionary *options = [command.arguments objectAtIndex:0];

    // Save off the Cordova callback ID so it can be used in the completion handlers.
    dropInUICommand = command;
    
    BTApplePayClient *applePayClient = [[BTApplePayClient alloc] initWithAPIClient:apiClient];
    [applePayClient paymentRequest:^(PKPaymentRequest * _Nullable paymentRequest, NSError * _Nullable error) {
        
        if (error != nil) {
            [self sendPluginError:error toCommand:dropInUICommand];
            dropInUICommand = nil;
            return;
        }
        
        [self parsePaymentRequest:options into:paymentRequest];
        // BTApplePayClient populates the PKPaymentRequest with the following fields:
        // countryCode, currencyCode, merchantIdentifier, supportedNetworks.
        //        paymentRequest.paymentSummaryItems = @[
        //            [PKPaymentSummaryItem summaryItemWithLabel:description
        //                                                amount:[NSDecimalNumber decimalNumberWithString: amount]]
        //        ];
        // paymentRequest.merchantIdentifier = applePayMerchantID;
        // paymentRequest.currencyCode = currencyCode;
        // paymentRequest.countryCode = countryCode;
        // paymentRequest.supportedNetworks = supportedNetworks;
        // paymentRequest.merchantCapabilities = PKMerchantCapability3DS;
        // paymentRequest.requiredBillingContactFields = [NSSet setWithArray:@[PKContactFieldName, PKContactFieldEmailAddress, PKContactFieldPhoneNumber]];
        // paymentRequest.requiredShippingContactFields = requiredShippingContactFields;
        
        PKPaymentAuthorizationViewController *viewController = [[PKPaymentAuthorizationViewController alloc] initWithPaymentRequest:paymentRequest];
        viewController.delegate = self;
        
        applePaySuccess = NO;
        
        // display ApplePay ont the rootViewController
        UIViewController *rootViewController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        
        [rootViewController presentViewController:viewController animated:YES completion:nil];
    }];
}

#pragma mark - Parsing

- (PKMerchantCapability)parseMerchantCapability:(NSSet*)set {
    if (!set) return PKMerchantCapability3DS;
    PKMerchantCapability ret = 0UL;
    for (NSString *value in set) {
        if ([value isEqualToString:@"3DS"]) ret |= PKMerchantCapability3DS;
        if ([value isEqualToString:@"EMV"]) ret |= PKMerchantCapabilityEMV;
        if ([value isEqualToString:@"Credit"]) ret |= PKMerchantCapabilityCredit;
        if ([value isEqualToString:@"Debit"]) ret |= PKMerchantCapabilityDebit;
    }
    return ret;
}

- (PKPaymentSummaryItemType)parsePaymentSummaryItemType:(NSString*)value {
    if (!value) return PKPaymentSummaryItemTypeFinal;
    if ([value isEqualToString:@"pending"]) return PKPaymentSummaryItemTypePending;
    return PKPaymentSummaryItemTypeFinal;
}

- (PKPaymentSummaryItem*)parsePaymentSummaryItem:(NSDictionary*)item {
    
    NSString *label = [item valueForKey:@"label"];
    NSDecimalNumber *amount = [BraintreePlugin decimalNumberIn:item forKey:@"amount"];
    PKPaymentSummaryItemType type = [self parsePaymentSummaryItemType: [BraintreePlugin stringIn:item forKey:@"type"]];
    if (@available(iOS 15.0, *)) {
        if ([item valueForKey:@"deferredDate"]) {
            PKDeferredPaymentSummaryItem *ret = [PKDeferredPaymentSummaryItem summaryItemWithLabel:label amount:amount type:type];
            ret.deferredDate = [BraintreePlugin dateIn:item forKey:@"deferredDate"];
            return ret;
        }
        if ([item valueForKey:@"intervalUnit"]) {
            PKRecurringPaymentSummaryItem *ret = [PKRecurringPaymentSummaryItem summaryItemWithLabel:label amount:amount];
            ret.startDate = [BraintreePlugin dateIn:item forKey:@"startDate"];
            ret.endDate = [BraintreePlugin dateIn:item forKey:@"endDate"];
            ret.intervalUnit = [BraintreePlugin calendarUnitIn:item forKey:@"intervalUnit" withDefault:NSCalendarUnitMonth];
            ret.intervalCount = [(NSNumber*)[item valueForKey:@"intervalCount"] integerValue];
            return ret;
        }
    }
    return [PKPaymentSummaryItem summaryItemWithLabel:label amount:amount type:type];
}

- (NSArray<PKPaymentSummaryItem*>*)parsePaymentSummaryItems:(NSSet*)set {
    if (!set) return nil;
    NSMutableArray<PKPaymentSummaryItem*>* ret = [NSMutableArray array];
    for (NSDictionary *item in set) {
        [ret addObject:[self parsePaymentSummaryItem:item]];
    }
    return ret;
}

- (CNPostalAddress*)parsePostalAddress:(NSDictionary*)dict {
    if (!dict) return nil;
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    CNMutablePostalAddress* address = [[CNMutablePostalAddress alloc] init];
    if (dict[@"street"]) address.street = dict[@"street"];
    if (dict[@"city"]) address.city = dict[@"city"];
    if (dict[@"state"]) address.state = dict[@"state"];
    if (dict[@"postalCode"]) address.postalCode = dict[@"postalCode"];
    if (dict[@"country"]) address.country = dict[@"country"];
    if (dict[@"ISOCountryCode"]) address.ISOCountryCode = dict[@"ISOCountryCode"];
    if (dict[@"subAdministrativeArea"]) address.subAdministrativeArea = dict[@"subAdministrativeArea"];
    if (dict[@"subLocality"]) address.subLocality = dict[@"subLocality"];
    return address;
}

- (PKContact*)parseContact:(NSDictionary*)dict {
    if (!dict) return nil;
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    PKContact* contact = [[PKContact alloc] init];
    if (dict[@"emailAddress"]) contact.emailAddress = dict[@"emailAddress"];
    if (dict[@"phoneNumber"]) contact.phoneNumber = dict[@"phoneNumber"];
    if (dict[@"name"]) contact.name = dict[@"name"];
    if (dict[@"postalAddress"]) contact.postalAddress = [self parsePostalAddress:dict[@"postalAddress"]];
    return contact;
}

- (PKShippingMethod*)parseShippingMethod:(NSDictionary*)dict {
    if (!dict) return nil;
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    PKPaymentSummaryItem *summary = [self parsePaymentSummaryItem:dict];
    if (!summary) return nil;
    PKShippingMethod *ret = [PKShippingMethod summaryItemWithLabel:summary.label amount:summary.amount type:summary.type];
    ret.identifier = dict[@"identifier"];
    ret.detail = dict[@"detail"];
    return ret;
}

- (NSArray<PKShippingMethod*>*)parseShippingMethods:(NSSet<NSDictionary*>*)set {
    if (!set) return nil;
    NSMutableArray<PKShippingMethod*> *ret = [NSMutableArray array];
    for (NSDictionary *value in set) {
        [ret addObject:[self parseShippingMethod:value]];
    }
    return ret;
}

- (void)parsePaymentRequest:(NSDictionary *)options into:(PKPaymentRequest*) request {
    if (!request.merchantIdentifier)
        request.merchantIdentifier = [BraintreePlugin stringIn:options forKey:@"merchantIdentifier"];
    request.merchantCapabilities = [self parseMerchantCapability: options[@"merchantIdentifier"]];
    if (!request.countryCode)
        request.countryCode = [BraintreePlugin stringIn:options forKey:@"countryCode"];
    if (!request.currencyCode)
        request.currencyCode = [BraintreePlugin stringIn:options forKey:@"currencyCode"];
    request.supportedCountries = options[@"supportedCountries"];
    request.paymentSummaryItems = [self parsePaymentSummaryItems: options[@"paymentSummaryItems"]];
    // this is filled by braintree.
    // request.supportedNetworks;
    request.billingContact = [self parseContact:options[@"billingContact"]];
    request.shippingContact = [self parseContact:options[@"shippingContact"]];
    request.requiredBillingContactFields = [self parseContactFields:options[@"requiredBillingContactFields"]];
    request.requiredShippingContactFields = [self parseContactFields:options[@"requiredShippingContactFields"]];
    if (@available(iOS 15.0, *)) {
        request.couponCode = options[@"couponCode"];
        request.supportsCouponCode = [BraintreePlugin boolIn:options forKey:@"supportsCouponCode" withDefault:NO];
    }
    request.shippingMethods = [self parseShippingMethods:options[@"shippingMethods"]];
}

- (NSDictionary*) formatBinData:(BTBinData*)binData into:(NSMutableDictionary*)dict {
    dict[@"prepaid"] = binData.prepaid;
    dict[@"healthcare"] = binData.healthcare;
    dict[@"debit"] = binData.debit;
    dict[@"durbinRegulated"] = binData.durbinRegulated;
    dict[@"commercial"] = binData.commercial;
    dict[@"payroll"] = binData.payroll;
    dict[@"issuingBank"] = binData.issuingBank;
    dict[@"countryOfIssuance"] = binData.countryOfIssuance;
    dict[@"productID"] = binData.productID;
    return dict;
}

- (NSDictionary*) formatApplePayCardNonce:(BTApplePayCardNonce*)nonce into:(NSMutableDictionary*)dict {
    dict[@"nonce"] = nonce.nonce;
    dict[@"type"] = nonce.type;
    if (nonce.binData) {
        dict[@"binData"] = [self formatBinData:nonce.binData into:[NSMutableDictionary dictionary]];
    }
    return dict;
}

- (NSString*) formatPaymentMethodType:(PKPaymentMethodType)type {
    switch (type) {
        case PKPaymentMethodTypeUnknown: return @"Unknown";
        case PKPaymentMethodTypeDebit: return @"Debit";
        case PKPaymentMethodTypeCredit: return @"Credit";
        case PKPaymentMethodTypePrepaid: return @"Prepaid";
        case PKPaymentMethodTypeStore: return @"Store";
        case PKPaymentMethodTypeEMoney: return @"EMoney";
    }
    return @"Unknown";
}

- (NSDictionary*) formatSecureElementPass:(PKSecureElementPass*)pass  API_AVAILABLE(ios(13.4)){
    return nil;
    // TODO: this isn't necessary with braintree (as far as I understand)
    // so I keep this for when we implement Apple Pay without Braintree.
}

- (NSArray<NSString*>*) formatPhoneNumbers:(NSArray<CNLabeledValue<CNPhoneNumber*>*>*)phoneNumbers {
    if (!phoneNumbers) return nil;
    NSMutableArray *array = [NSMutableArray array];
    for (CNLabeledValue<CNPhoneNumber*>* number in phoneNumbers) {
        [array addObject:[number.value stringValue]];
    }
    return array;
}

- (NSArray<NSString*>*) formatLabeledStringArray:(NSArray<CNLabeledValue<NSString*>*>*)inArray {
    if (!inArray) return nil;
    NSMutableArray *array = [NSMutableArray array];
    for (CNLabeledValue<NSString*>* element in inArray) {
        [array addObject:element.value];
    }
    return array;
}

- (NSDictionary*) formatPostalAddress:(CNPostalAddress*)address {
    if (!address) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"street"] = address.street;
    dict[@"city"] = address.city;
    dict[@"state"] = address.state;
    dict[@"postalCode"] = address.postalCode;
    dict[@"country"] = address.country;
    dict[@"ISOCountryCode"] = address.ISOCountryCode;
    dict[@"subAdministrativeArea"] = address.subAdministrativeArea;
    dict[@"subLocality"] = address.subLocality;
    return dict;
}

- (NSArray<NSDictionary*>*) formatPostalAddresses:(NSArray<CNLabeledValue<CNPostalAddress*>*>*)addresses {
    if (!addresses) return nil;
    NSMutableArray<NSDictionary*> *array = [NSMutableArray array];
    for (CNLabeledValue<CNPostalAddress*>* element in addresses) {
        [array addObject:[self formatPostalAddress:element.value]];
    }
    return array;
}

- (NSDictionary*) formatCNContact:(CNContact*)contact {
    if (!contact) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (contact.contactType == CNContactTypePerson) {
        dict[@"contactType"] = @"Person";
    } else if (contact.contactType == CNContactTypeOrganization) {
        dict[@"contactType"] = @"Organization";
    }
    dict[@"identifier"] = contact.identifier;
    dict[@"namePrefix"] = contact.namePrefix;
    dict[@"givenName"] = contact.givenName;
    dict[@"middleName"] = contact.middleName;
    dict[@"familyName"] = contact.familyName;
    dict[@"previousFamilyName"] = contact.previousFamilyName;
    dict[@"nameSuffix"] = contact.nameSuffix;
    dict[@"nickname"] = contact.nickname;

    dict[@"organizationName"] = contact.organizationName;
    dict[@"departmentName"] = contact.departmentName;
    dict[@"jobTitle"] = contact.jobTitle;

    dict[@"phoneticGivenName"] = contact.phoneticGivenName;
    dict[@"phoneticMiddleName"] = contact.phoneticMiddleName;
    dict[@"phoneticFamilyName"] = contact.phoneticFamilyName;
    dict[@"phoneticOrganizationName"] = contact.phoneticOrganizationName;

    dict[@"note"] = contact.note;
    dict[@"phoneNumbers"] = [self formatPhoneNumbers: contact.phoneNumbers];
    dict[@"emailAddresses"] = [self formatLabeledStringArray:contact.emailAddresses];
    // @property (readonly, copy, NS_NONATOMIC_IOSONLY) NSArray<CNLabeledValue<CNPostalAddress*>*>           *postalAddresses;
    dict[@"urlAddresses"] = [self formatLabeledStringArray:contact.urlAddresses];
    //    @property (readonly, copy, NS_NONATOMIC_IOSONLY) NSArray<CNLabeledValue<CNContactRelation*>*>         *contactRelations;
    //    @property (readonly, copy, NS_NONATOMIC_IOSONLY) NSArray<CNLabeledValue<CNSocialProfile*>*>           *socialProfiles;
    //    @property (readonly, copy, NS_NONATOMIC_IOSONLY) NSArray<CNLabeledValue<CNInstantMessageAddress*>*>   *instantMessageAddresses;
    //    @property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSDateComponents *birthday;
    //    @property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSDateComponents *nonGregorianBirthday;
    return dict;
}

- (NSDictionary*) formatPaymentMethod:(PKPaymentMethod*)method {
    if (!method) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"displayName"] = method.displayName;
    dict[@"network"] = method.network; // it's a NSString already
    dict[@"type"] = [self formatPaymentMethodType:method.type];
    if (@available(iOS 13.4, *)) {
        dict[@"secureElementPass"] = [self formatSecureElementPass: method.secureElementPass];
    }
    if (@available(iOS 13.0, *)) {
        dict[@"billingAddress"] = [self formatCNContact:method.billingAddress];
    }
    return dict;
}

- (NSDictionary*) formatPaymentToken:(PKPaymentToken*)token {
    if (!token) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"paymentMethod"] = [self formatPaymentMethod:token.paymentMethod];
    dict[@"transactionIdentifier"] = token.transactionIdentifier;
    dict[@"paymentData"] = [token.paymentData base64EncodedStringWithOptions:0UL];
    return dict;
}

- (NSDictionary*) formatShippingMethod:(PKShippingMethod*)method {
    if (!method) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"identifier"] = method.identifier;
    dict[@"detail"] = method.detail;
    // dict[@"dateComponentsRange"] = method.dateComponentsRange; NOT SUPPORTED
    return dict;
}

- (NSDictionary*) formatPayment:(PKPayment*)payment into:(NSMutableDictionary*)dict {
    // A PKPaymentToken which contains an encrypted payment credential.
    dict[@"token"] = [self formatPaymentToken:payment.token];
    dict[@"shippingMethod"] = [self formatShippingMethod:payment.shippingMethod];
    dict[@"shippingContact"] = payment.shippingContact;
    dict[@"billingContact"] = [self formatPKContact:payment.billingContact];
    return dict;
}

- (NSDictionary*) formatPKContact:(PKContact*)contact {
    if (!contact) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    /** Contact's name. */
    dict[@"name"] = contact.name;
    dict[@"emailAddress"] = contact.emailAddress;
    dict[@"phoneNumber"] = contact.phoneNumber;
    dict[@"postalAddress"] = [self formatPostalAddress:contact.postalAddress];
    return dict;
}

#pragma mark - PKPaymentAuthorizationViewControllerDelegate

- (void)paymentAuthorizationViewController:(PKPaymentAuthorizationViewController *)controller didAuthorizePayment:(PKPayment *)payment handler:(void (^)(PKPaymentAuthorizationResult * _Nonnull))completion {
    applePaySuccess = YES;
    
    BTAPIClient *apiClient = [BraintreePlugin getClient];
    // Ensure the client has been initialized.
    if (!apiClient) {
        CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"The Braintree client is not ready."];
        [self.commandDelegate sendPluginResult:res callbackId:dropInUICommand.callbackId];
        dropInUICommand = nil;
        return;
    }
    BTApplePayClient *applePayClient = [[BTApplePayClient alloc] initWithAPIClient:apiClient];
    
//    NSMutableDictionary * contactInfo = [NSMutableDictionary dictionary];
//    [contactInfo setDictionary:@{
//        @"firstName": ![[[payment shippingContact] name] givenName] ? [NSNull null] : [[[payment shippingContact] name] givenName],
//        @"lastName": ![[[payment shippingContact] name] familyName] ? [NSNull null] : [[[payment shippingContact] name] familyName],
//        @"emailAddress": ![[payment shippingContact] emailAddress] ? [NSNull null] : [[payment shippingContact] emailAddress],
//        @"phoneNumber": ![[payment shippingContact] phoneNumber] ? [NSNull null] : [[[payment shippingContact] phoneNumber] stringValue]
//    }];
    
    [applePayClient tokenizeApplePayPayment:payment completion:^(BTApplePayCardNonce *applePayCardNonce, NSError *error) {
        if (applePayCardNonce) {
            // On success, send nonce to your server for processing.
            // NSDictionary * paymentInfo = [self getPaymentUINonceResult:tokenizedApplePayPayment];
            // [contactInfo addEntriesFromDictionary:paymentInfo];
            NSMutableDictionary *message = [NSMutableDictionary dictionary];
            message[@"applePayCardNonce"] = [self formatApplePayCardNonce:applePayCardNonce into:[NSMutableDictionary dictionary]];
            message[@"payment"] = [self formatPayment:payment into:[NSMutableDictionary dictionary]];
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:message];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:dropInUICommand.callbackId];
            dropInUICommand = nil;
            
            // Then indicate success or failure via the completion callback, e.g.
            completion([[PKPaymentAuthorizationResult alloc] initWithStatus:PKPaymentAuthorizationStatusSuccess errors:nil]);
        } else {
            // Tokenization failed. Check `error` for the cause of the failure.
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Apple Pay tokenization failed"];
            
            [self.commandDelegate sendPluginResult:pluginResult callbackId:dropInUICommand.callbackId];
            dropInUICommand = nil;
            
            // Indicate failure via the completion callback:
            completion([[PKPaymentAuthorizationResult alloc] initWithStatus:PKPaymentAuthorizationStatusFailure errors:nil]);
        }
    }];
    
}

- (void)paymentAuthorizationViewControllerDidFinish:(PKPaymentAuthorizationViewController *)controller {
    UIViewController *rootViewController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    
    [rootViewController dismissViewControllerAnimated:YES completion:nil];
    
    // if not success, fire cancel event
    if (!applePaySuccess) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK  messageAsDictionary:@{
            @"userCancelled": @YES
        }];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:dropInUICommand.callbackId];
        dropInUICommand = nil;
    }
}

#pragma mark - BTViewControllerPresentingDelegate

- (void)paymentDriver:(id)driver requestsPresentationOfViewController:(UIViewController *)viewController {
    UIViewController *rootViewController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    [rootViewController presentViewController:viewController animated:YES completion:nil];
}

- (void)paymentDriver:(id)driver requestsDismissalOfViewController:(UIViewController *)viewController {
    UIViewController *rootViewController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    [rootViewController dismissViewControllerAnimated:YES completion:nil];
}

/*
#pragma mark - BTThreeDSecureRequestDelegate

- (void)onLookupComplete:(BTThreeDSecureRequest *)request lookupResult:(BTThreeDSecureResult *)result next:(void(^)(void))next {
    threeDResultNonce = result.tokenizedCard.nonce;
    next();
}

#pragma mark - Helpers

- (NSArray*)mapCardTypes:(NSSet*)cardTypes {
    NSMutableArray * networks = [[NSMutableArray alloc] init];
    
    for (NSString * cardType in cardTypes) {
        PKPaymentNetwork network;
        
        if ([cardType isEqualToString:@"visa"]) {
            network = PKPaymentNetworkVisa;
        } else if ([cardType isEqualToString:@"mastercard"]) {
            network = PKPaymentNetworkMasterCard;
        } else if ([cardType isEqualToString:@"amex"]) {
            network = PKPaymentNetworkAmex;
        } else {
            NSLog(@"unsupported card type: %@", cardType);
        }
        
        if (network != nil) {
            [networks addObject:network];
        }
    }
    
    return networks;
}
 */

- (NSSet<PKContactField>*)parseContactFields:(NSSet*)contactFields {
    NSMutableArray *fields = [[NSMutableArray alloc] init];
    
    for (NSString *contactField in contactFields) {
        PKContactField field;
        
        if ([contactField isEqualToString:@"name"]) {
            field = PKContactFieldName;
        } else if ([contactField isEqualToString:@"emailAddress"]) {
            field = PKContactFieldEmailAddress;
        } else if ([contactField isEqualToString:@"phoneNumber"]) {
            field = PKContactFieldPhoneNumber;
        } else if ([contactField isEqualToString:@"postalAddress"]) {
            field = PKContactFieldPostalAddress;
        } else if ([contactField isEqualToString:@"phoneticName"]) {
            field = PKContactFieldPhoneticName;
        } else {
            NSLog(@"unsupported contact field: %@", contactField);
        }
        
        if (field != nil) {
            [fields addObject:field];
        }
    }
    
    return [NSSet setWithArray:fields];
}

/// Send an error back to the caller, log it to the console.
- (void) sendPluginError: (NSError*) error toCommand:(CDVInvokedUrlCommand *)command {
    [self error:[NSString stringWithFormat:@"Code: %zd", [error code]]];
    [self error:[NSString stringWithFormat:@"Description: %@", [error localizedDescription]]];
    NSString *errorString = [NSString stringWithFormat:@"%zd|%@", error.code, error.localizedDescription];
    CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorString];
    [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
}

/// Log a message to the console
- (void) log:(int)level message:(NSString*)message {
    if (level >= verbosityLevel) {
        NSLog(@"[%@] %@", LOG_PREFIX, message);
        if (loggerCallback != nil) {
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];
            pluginResult.keepCallback = [NSNumber  numberWithBool:YES];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:loggerCallback];
        }
    }
}

- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

@end

