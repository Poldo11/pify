import fragments/image.{image_fragment}
import fragments/seo.{seo_fragment}

pub fn product_fragment() -> String {
  "
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
" <> image_fragment() <> seo_fragment()
}
