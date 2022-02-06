#/bin/bash
set -euo pipefail

# Generate cloud-init input string.
CLOUD_INIT_STR=$(cat << EOSTR 
#cloud-config
package_upgrade: true
packages:
  - nginx
  - nodejs
  - npm
write_files:
  - owner: www-data:www-data
  - path: /etc/nginx/sites-available/default
    content: |
      server {
        listen 80;
        location / {
          proxy_pass http://localhost:3000;
          proxy_http_version 1.1;
          proxy_set_header Upgrade \$http_upgrade;
          proxy_set_header Connection keep-alive;
          proxy_set_header Host \$host;
          proxy_cache_bypass \$http_upgrade;
        }
      }
  - owner: azureuser:azureuser
  - path: /home/azureuser/myapp/index.js
    content: |
      var express = require('express')
      var app = express()
      var os = require('os');
      app.get('/', function (req, res) {
        res.send('Hello World from host ' + os.hostname() + '!')
      })
      app.listen(3000, function () {
        console.log('Hello world app listening on port 3000!')
      })
runcmd:
  - service nginx restart
  - cd "/home/azureuser/myapp"
  - npm init
  - npm install express -y
  - nodejs index.js
final_message: >
    Run az network public-ip show to obtain IP address of load balancer.  Open web browser to test functionality
EOSTR
)

# Double quotes around CLOUD_INIT_STR preserve newlines in stdout.  Required by cloud-init.
echo "${CLOUD_INIT_STR}" | base64 | tr -d '\n\r' | awk '{printf "{\"cloudInitFileAsBase64\": \"%s\"}", $1}' > ${AZ_SCRIPTS_OUTPUT_PATH}
