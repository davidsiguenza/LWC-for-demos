# Post Install Instructions

You will be able to define a credit Limit (Field available in the Account object) and validate that the total of the cart is not higher than the credit limit. If it is higher, the user will not be able to checkout with a Purchase Order, but only with a Credit Card.

- Give visibility to site user (Profile > SDO-Cusotmer Community Plus)
  Apex:
  - CheckoutCreditController
- Add Componet to Checkout Page
  - Credit Validator

Add the following fields to the Account object: - Credit Limit (THis is the field that we have to manage to let them have credit to buy with Purchase Order)

IF not an SDO - Create the field Credit Limit --> CreditLimit\_\_c in your Account object
