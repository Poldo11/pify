import fragments/products.{product_fragment}

// import productFragment from '../fragments/products'

pub fn cart_fragment() {
  "
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
  " <> product_fragment()
}
