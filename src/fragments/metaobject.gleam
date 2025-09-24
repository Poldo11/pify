pub fn metaobject_fragment() {
  // GraphQL
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
}
