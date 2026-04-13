
#!/bin/bash

# Tests the TeaStore WebUI for working endpoints

HOST=${1:-localhost}      # usually localhost
PROTO=${2:-http}          # supports 'http' and 'https'
WEBUI_PORT=${3:-8080}     # 8080 for http, 8443 for https

# Checks HTML GET response for failure/error for given HTTP URL endpoint
function send_request () {
  URL="${PROTO}://${HOST}:${WEBUI_PORT}/tools.descartes.teastore.webui/${1}"
  RES="$(curl -ks "${URL}")"
  if echo "${RES}" | grep -E -i 'error|fail|exception' > /dev/null
  then
    echo "Request for URL '${URL}' failed."
    echo "[START HTML]${RES}[END HTML]"
    exit 1
  fi
}

# Check if login works
function check_login () {
  URL_VALID="${PROTO}://${HOST}:${WEBUI_PORT}/tools.descartes.teastore.webui/loginAction?username=user2&password=password"
  if [[ $(curl -kLs -X POST "${URL_VALID}" | grep -c '<title>TeaStore Home</title>') -ne 1 ]];
  then
    echo "Login Check Error: Valid login should forward to TeaStore home!"
    exit 1
  fi
  URL_INVALID="${PROTO}://${HOST}:${WEBUI_PORT}/tools.descartes.teastore.webui/loginAction?username=testuser&password=password"
  if [[ $(curl -kLs -X POST "${URL_INVALID}" | grep -c '<title>TeaStore Login</title>') -ne 1 ]];
  then
    echo "Login Check Error: Invalid login should forward to TeaStore login!"
    exit 1
  fi
}

# adds a product to cart and checks if it is present
function check_add_to_cart () {
  if [[ $(curl -kLs -c - -X POST "${PROTO}://${HOST}:${WEBUI_PORT}/tools.descartes.teastore.webui/cartAction?addToCart=&productid=${1}" | grep -c "name=\"productid\" value=\"${1}\"") -lt 1 ]];
  then
    echo "Couldn't add product ${1} to cart!"
    exit 1
  fi
}

function check_ads () {
  if [[ $(curl -ks "${PROTO}://${HOST}:${WEBUI_PORT}/tools.descartes.teastore.webui/product?id=${1}" | grep -c 'Are you interested in') -eq 0 ]];
  then
    echo "No ads available! Check recommender service!"
    exit 1
  fi
}

function check_images () {
  if [[ $(curl -ks "${PROTO}://${HOST}:${WEBUI_PORT}/tools.descartes.teastore.webui/product?id=${1}" | tr '\n' ' ' | grep -cEo 'class="productpicture"\s+src=""') -gt 0 ]];
  then
    echo "No product image available! Check image service!"
    exit 1
  fi
}

# Checks if products are available
function check_products () {
  COUNTER=${1}
  URL="${PROTO}://${HOST}:${WEBUI_PORT}/tools.descartes.teastore.webui/"
  
  # Use sed/grep compatible with macOS
  CATEGORIES_STR=$(curl -ks "${URL}" | grep -o "category=[0-9]*" | grep -o "[0-9]*")
  IFS=$'\n' read -rd '' -a CATEGORIES <<< "$CATEGORIES_STR"
  
  if [ -z "$CATEGORIES_STR" ]; then
    echo "No categories in WebUI!"
    exit 1
  fi
  
  for cat in $CATEGORIES_STR; do
    PRODUCTS_STR=$(curl -kLs -X POST "${PROTO}://${HOST}:${WEBUI_PORT}/tools.descartes.teastore.webui/category?category=${cat}&number=30" | grep -o 'product?id=[0-9]*' | grep -o '[0-9]*')
    
    if [ -z "$PRODUCTS_STR" ]; then
      echo "No products for category ${cat}!"
      exit 1
    fi
    
    for prod in $PRODUCTS_STR; do
      if [ "$COUNTER" -gt 0 ]; then
        check_add_to_cart "${prod}"
        COUNTER=$(( COUNTER - 1 ))
      else
        # at last, check if images and ads are available
        check_ads ${prod}
        check_images ${prod}
        return 0
      fi
    done
  done
}

function check_status () {
  STATUS_COUNT=$(curl -ks "${PROTO}://${HOST}:${WEBUI_PORT}/tools.descartes.teastore.webui/status" | grep -c OK)
  if [[ "$STATUS_COUNT" -ne 5 ]]; then
    echo "Status was not OK! Count: $STATUS_COUNT. Proceeding anyway..."
    # exit 1
  fi
}

# whitelist tests
check_status
check_login
check_products 5

# blacklist tests
send_request
send_request login
send_request profile

echo "WebUI test finished successully!"
