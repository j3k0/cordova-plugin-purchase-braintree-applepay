# ApplePay for Braintree for Cordova

This is [Cordova](http://cordova.apache.org/) plugin extends the [Cordova Purchase Plugin](https://github.com/j3k0/cordova-plugin-purchase/)'s [Braintree Adapter](https://github.com/j3k0/cordova-plugin-purchase/) to add Apple Pay support.

This plugin requires at least cordova-plugin-purchase-braintree of at least the same version number.

## Installing

The plugin identifier is `cordova-plugin-purchase-braintree-applepay`. Here's how to adding it to your app with the cordova CLI:

```sh
cordova plugin add cordova-plugin-purchase-braintree-applepay --variable APPLE_PAY_MERCHANT_ID=merchant.my.app.com
```

## Usage

### Initialization

Initialize the purchase plugin with the Braintree adapter enabled. It will detect that this extension is available and offer the Apple Pay payment option when possible.

You can customize it by passing additional options at initialization:

```ts
store.initialize([{
  platform: CdvPurchase.Platform.BRAINTREE,
  options: {
    applePay: {
      // Apple Pay would like to use the company name as a description for the payment total
      companyName: 'The Company, LLC'

      // Optionally, you can customize the full payment request.
      preparePaymentRequest: (request) => {
        // Return an ApplePay.PaymentRequest. For details see:
        // - https://github.com/j3k0/cordova-plugin-purchase/blob/master/api/interfaces/CdvPurchase.ApplePay.PaymentRequest.md
        // - https://developer.apple.com/documentation/passkit/pkpaymentrequest/ for details.
        return {
          merchantCapabilities: [CdvPurchase.ApplePay.MerchantCapability.EMV],
          shippingMethods = [{
            label: "Free Shipping",
            amount: "0.00",
            identifier: "free",
            detail: "Arrive by July 2"
          }, {
            label: "Standard Shipping",
            amount: "3.00",
            identifier: "standard",
            detail: "Arrive by June 29"
          }, {
            label: "Express Shipping",
            amount: "9.00",
            identifier: "express",
            detail: "Ships withing 24h"
          }],
          // see https://developer.apple.com/documentation/passkit/pkpaymentrequest/1619231-paymentsummaryitems
          paymentSummaryItems: [{
            amount: '1.50',
            label: 'Some item'
          }, {
            amount: '3.00',
            label: 'Some other item'
          }, {
            amount: '9.00',
            label: 'Express Shipping',
            type: 'pending'
          }, {
            amount: '-3.50',
            label: 'Discount'
          }, {
            // The last entry is the grand total
            amount: '10.00',
            label: 'Company, LLC',
            type: 'pending'
          }]
        }
      }
    }
  }
}];
```

For the full reference, see [Braintree.AdapterOptions API](https://github.com/j3k0/cordova-plugin-purchase/blob/master/api/interfaces/CdvPurchase.Braintree.AdapterOptions.md) for reference. You can do things like prefill the shipping or billing address, limit the available payment methods, limit the countries you accept payment from, etc.

### Making a purchase

Use the `store.requestPayment()` method to initiate a payment with Braintree.

- `amountMicros` and `currency` are required.
- If `result.isError` is set, the returned value is an error.
  - Check `result.code`, `PAYMENT_CANCELLED` means the user closed the modal window.
  - Other error codes means something went wrong.

```ts
store.requestPayment({
  platform: CdvPurchase.Platform.BRAINTREE,
  productIds: ['my-product-1', 'my-product-2'], // Use anything, for reference
  amountMicros: 1990000,
  currency: 'USD',
  description: 'This this the description of the payment request',
}, {})
.failed(error => {
  // payment request failed
  showAlert(error.message);
})
.approved(transaction => {
  // payment request approved
})
.finished(transaction => {
  // payment finished
})
.cancelled(() => {
  // user cancelled by closing the dialog window
});
```

Once the client gets the initial approval, the `"approved"` event is triggered. It's the job of
the receipt validation service to create and submit a transaction to Braintree.

Once again, [Iaptic](https://www.iaptic.com/) has built-in support for Braintree, so this part is already covered if your app is integrated with [Iaptic](https://www.iaptic.com/). If now, implement the server side call using values provided by the receipt validation call.

### Dynamically disable Apple Pay

You can choose to dynamically disable Apple Pay by passing `applePayDisabled` as show below to the `store.requestPayment()` function:

```ts
store.requestPayment({
  /* ... */
}, {
  braintree: {
    dropInRequest: {
      applePayDisabled: true,
    }
  }
});
```

## Licence

The MIT License

Copyright (c) 2022, Jean-Christophe Hoelt and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

```
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
