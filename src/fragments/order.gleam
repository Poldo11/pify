pub fn money_fields_fragment() {
  "
  fragment MoneyFields on MoneyV2 {
      amount
      currencyCode
    }
  "
}

pub fn money_bag_fields_fragment() {
  "
    fragment MoneyBagFields on MoneyBag {
      shopMoney {
        ...MoneyFields
      }
      presentmentMoney {
        ...MoneyFields
      }
    }
  "
}

pub fn line_items_fields_fragment() {
  "
  fragment LineItemFields on LineItem {
    id
    name
    title
    quantity
  	discountAllocations {
    allocatedAmountSet {
      presentmentMoney {
        amount
        currencyCode
      }
    }
    discountApplication {
      allocationMethod
      value {
        ...MoneyFields
      }
    }
      discountApplication {
        ...DiscountApplicationFields
      }
  }
    requiresShipping
    sku
    taxable
    product {
    	id
      handle
    }
    variant {
      id
      price
      product {
        id
        handle
      }
      title
    }
    originalTotalSet {
      ...MoneyBagFields
    }
    discountedTotalSet {
      ...MoneyBagFields
    }
    customAttributes {
      key
      value
      }
    }
  "
}

pub fn discount_application_fields_fragment() {
  "
    fragment DiscountApplicationFields on DiscountApplication {
      allocationMethod
      targetSelection
    targetType
      value {
        ... on MoneyV2 {
          ...MoneyFields
        }
        ... on PricingPercentageValue {
          percentage
        }
      }
    ... on DiscountCodeApplication {
      code
    }
    ... on AutomaticDiscountApplication {
      title
      }
    }
  "
}

pub fn address_fields_fragment() {
  "
    fragment AddressFields on MailingAddressConnection {
      pageInfo {
        hasNextPage
        endCursor
      }
      edges {
        cursor
        node {
          ... on MailingAddress{
            name
          }
        }
      }
      nodes{
        id
        address1
        address2
        name
        firstName
        lastName
      city
      province
      country
      countryCodeV2
      formatted
      formattedArea
      timeZone
        zip
      }
    }
  "
}

pub fn customer_fields_fragments() {
  "
    fragment CustomerFields on Customer {
    id
    displayName
    firstName
    lastName
    numberOfOrders
    note
    tags
    updatedAt
    verifiedEmail
    defaultAddress{
      name
      phone
      timeZone
      id
      address1
      address2
      zip
      city
      company
      country
      countryCodeV2
      formatted
      formattedArea
    }
    defaultEmailAddress {
      emailAddress
      marketingOptInLevel
      marketingState
      validFormat
    }
    defaultPhoneNumber {
      phoneNumber
      marketingOptInLevel
      marketingState
    }
  }
  "
}

pub fn order_node_fields() {
  "
    fragment OrderNodeFields on Order {
      id
      name
      note
      createdAt
      updatedAt
    processedAt
    cancelledAt
    cancelReason
    closed
    closedAt
    confirmed
    test
    currentSubtotalLineItemsQuantity
    currentTotalWeight
    displayFinancialStatus
    displayFulfillmentStatus
    edited
    requiresShipping
    currentSubtotalPriceSet {
      ...MoneyBagFields
    }
    currentTotalPriceSet {
      ...MoneyBagFields
    }
    currentTotalDiscountsSet {
      ...MoneyBagFields
    }
    currentTotalTaxSet {
      ...MoneyBagFields
    }
    originalTotalPriceSet {
      ...MoneyBagFields
    }
    app {
      id
      name
    }
    customer {
      ...CustomerFields
    }
    discountApplications(first: 10) {
      edges {
        node {
          ...DiscountApplicationFields
        }
      }
    }
    tags
    taxExempt
    taxesIncluded
    lineItems(first: 25) {
      edges {
        node {
          ...LineItemFields
        }
      }
    }
    fulfillments {
      id
      createdAt
      displayStatus
      estimatedDeliveryAt
      status
      trackingInfo {
        company
        number
        url
      }
    }
    refunds {
      id
      createdAt
      note
    }
    transactions {
      id
      createdAt
      errorCode
      gateway
      kind
      processedAt
      status
      test
    }
  }
  "
}
