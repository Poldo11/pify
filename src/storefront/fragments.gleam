pub const image_fragment = // GraphQL
"
	fragment image on Image {
		url
		altText
		width
		height
	}
  "

pub const metafield_fragment = // GraphQL
"
  fragment metafield on Metafield {
  key
  value
  type
  }
  "

pub const metaobject_fragment = // GraphQL
"
  	fragment metaobject on Metaobject {
  		id
  		type
  		fields {
  			key
  			value
  			type
  			reference {
  				... on Metaobject {
  					id
  					type
  					fields {
  						key
  						value
  					}
  				}
  			}
  		}
  	}
  "

pub const money_fields_fragment = "
  fragment MoneyFields on MoneyV2 {
      amount
      currencyCode
    }
  "

pub const money_bag_fields_fragment = "
    fragment MoneyBagFields on MoneyBag {
      shopMoney {
        ...MoneyFields
      }
      presentmentMoney {
        ...MoneyFields
      }
    }
  "

pub const line_items_fields_fragment = "
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

pub const discount_application_fields_fragment = "
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

pub const address_fields_fragment = "
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

pub const customer_fields_fragments = "
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

pub const order_node_fields = "
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

pub const product_fragment = "
	fragment product on Product {
		id
		handle
		availableForSale
		title
		description
		descriptionHtml
		vendor
		options {
			id
			name
			values
		}
		priceRange {
			maxVariantPrice {
				amount
				currencyCode
			}
			minVariantPrice {
				amount
				currencyCode
			}
		}
		compareAtPriceRange {
			maxVariantPrice {
				amount
				currencyCode
			}
			minVariantPrice {
				amount
				currencyCode
			}
		}
		variants(first: 250) {
			edges {
				node {
					id
					title
					availableForSale
					selectedOptions {
						name
						value
					}
					price {
						amount
						currencyCode
					}
				}
			}
		}
		featuredImage {
			...image
		}
		images(first: 20) {
			edges {
				node {
					...image
				}
			}
		}
		seo {
			...seo
		}
		metafields(
		{ namespace: \"metafield\", key: \"width\" }
						{ namespace: \"metafield\", key: \"height\" }
						{ namespace: \"metafield\", key: \"thickness\" }
						{ namespace: \"metafield\", key: \"pages\" }
						{ namespace: \"metafield\", key: \"categories\" }
						{ namespace: \"metafield\", key: \"language\" }
						{ namespace: \"metafield\", key: \"format\" }
						{ namespace: \"custom\", key: \"author\" }
						{ namespace: \"custom\", key: \"publisher\" }
						{ namespace: \"custom\", key: \"related-authors\" }
						{ namespace: \"custom\", key: \"people-who-worked\" }
						{ namespace: \"custom\", key: \"translator\" }
						{ namespace: \"custom\", key: \"related-books\" }
						{ namespace: \"shopify\", key: \"genre\" }
						{ namespace: \"shopify\", key: \"book-cover-type\" }
						{ namespace: \"shopify\", key: \"target-audience\" }
					]
		) {
			key
			namespace
			value
			type
			references(first: 5) {
				nodes {
					... on Metaobject {
						id
						type
						fields {
							key
							value
						}
					}
				}
			}
		}
		tags
		updatedAt
	}
"
  <> image_fragment
  <> seo_fragment

pub const seo_fragment = "
  fragment seo on SEO {
  description
  title
  }
  "

pub const cart_fragment = "
    	fragment cart on Cart {
    		id
    		checkoutUrl
    		cost {
    			subtotalAmount {
    				amount
    				currencyCode
    			}
    			totalAmount {
    				amount
    				currencyCode
    			}
    			totalTaxAmount {
    				amount
    				currencyCode
    			}
    		}
    		lines(first: 100) {
    			edges {
    				node {
    					id
    					quantity
    					attributes {
    						key
    						value
    					}
    					cost {
    						totalAmount {
    							amount
    							currencyCode
    						}
    					}
    					merchandise {
    						... on ProductVariant {
    							id
    							title
    							compareAtPrice {
    								amount
    								currencyCode
    							}
    							selectedOptions {
    								name
    								value
    							}
    							product {
    								...product
    							}
    						}
    					}
    				}
    			}
    		}
    		totalQuantity
    	}
    "
  <> product_fragment
