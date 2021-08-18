# Laravel-Vue-Docker
_Create a Laravel &amp; Vue Front-end Development Stack_

# Introduction
The purpose of this guide is to make your application as easy as possible to self deploy on the developers side without them bothering with installing mysql, nginx, and a ton of stuff just to start doing what they do best.

# Requirements
Before we start, we're gonna need a few dependencies to get this project underway

> Docker<br>
> Docker-Compose<br>
> Node/npm

To install Docker & Docker-Compose simply use the following commands
```javascript
# Install Docker
$ curl -fsSL https://get.docker.com -o get-docker.sh
$ sudo sh get-docker.sh
$ sudo groupadd docker
$ sudo usermod -aG docker $USER
$ newgrp docker
$ sudo rm -f get-docker.sh
# Install Docker-Compose
$ sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
$ sudo chmod +x /usr/local/bin/docker-compose
```

For npm go with nvm for ease of use
```javascript
$ curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
$ export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
$ nvm install node
```

# Preparing Laravel Backend Api
Rather than go through all the hassle of installing php/composer and running the composer command to generate the laravel project you can simply use the following command to create the laravel project
```javascript
curl -s https://laravel.build/folder-name | bash
```
※**Notice**: `Change folder-name in the command with any folder name you'd like`<br/>
Lets delete the package.json file in the root directory since we are not gonna be using it

# Folder Structure
Add the missing folders from the following structure and leave them empty for now
```javascript
.
├── tools
│   ├── dockerfiles
│   │   ├── ci
│   │   ├── dev-images
│   │   └── prod-images
│   └── scripts
│   │   ├── ci
│   │   ├── local
├── app
├── bootstrap
├── config
├── database
├── public
├── resources
├── routes
├── server
│   └── config
├── storage
├── tests
├── client
└── vendor
```

# Install Front-end
Lets go with vue.js, inside the root folder run the following command
```javascript
$ npm install -g @vue/cli
$ vue create client # You can use `vue ui` as an alternative to the cli to generate an interface and guide you through the steps
```
Now you're gonna be greeted with a lot of options to choose from, those are entirely up to you `choose with the space bar` and I recommend having `vuex router`

**※Notice**: _Avoid choosing a unit/e2e/node-sass preprocessor with typescript as it can have some build problems / errors, simply install those after you finish compiling the project with npm like_
```javascript
$ npm install jest
```
in case the project is created with a repo simply do a
```javascript
sudo rm -rf client/.git
```

# Preparing Docker Images
Okay now for the fun part, lets start creating the images the application will use

* Backend image
in `tools/dockerfiles/dev-images/` create `backend.dockerfile`
```javascript
# ! Image
FROM php:8.0.6-fpm-alpine3.12

# ? Set Working Directory
WORKDIR /var/www/html

# ? Install Mysql Extensions
RUN docker-php-ext-install pdo pdo_mysql

# ? Install and enable PHP Redis extension
# ? Redis extension is not provided with the PHP Source
# ? pecl install will download and compile redis
# ? docker-php-ext-enable will enable it
# ? finally apk del to maintain a small image size
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
 && pecl install redis-5.3.4 \
 && docker-php-ext-enable redis \
 && apk del .build-deps

# ? Install & Configure gd
RUN apk add --no-cache freetype libpng libjpeg-turbo freetype-dev libpng-dev libjpeg-turbo-dev && \
  docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
  NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) && \
  docker-php-ext-install -j$(nproc) gd && \
  apk del --no-cache freetype-dev libpng-dev libjpeg-turbo-dev

# ? Install git (required by Composer)
RUN apk add git

# *** Install Composer
RUN php -r "readfile('http://getcomposer.org/installer');" | php -- --install-dir=/usr/bin/ --filename=composer
```

* Client image
in `tools/dockerfiles/dev-images/` create `client.dockerfile`
```javascript
# ! Image
FROM node:14-alpine

# ? Set Working Directory
WORKDIR /var/www/client

# * Install PM2 to serve the app
RUN npm install pm2 -g

# ? Serve the application on start
CMD command pm2 serve ./dist/ 8080 --spa --watch && pm2 log
```
those are the images we'll need for now

# php & php-fpm config
whether or not you want to change something in `php.ini` or `www.conf` you should at least have them exposed in case you wanna edit them later
we'll do that by creating them and linking them inside the containers

in `server/config` create `php.ini` & `www.conf` files
* php.ini
* www.conf

# nginx Config
We are going to need a self signed certificate, inside the project's root directory run the following command
```javascript
$ sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ./server/key.pem -out ./server/cert.pem
```
notice: skip all the prompts with enter
once generated, lets open up `key.pem` permissions so that we can add it to the repo
```
sudo chmod 644 server/key.pem
```
for nginx config, create a `default.conf` file inside the server folder and paste the following content
```javascript
server
{
    # Listen To HTTPS port
    listen                  443 ssl http2;
    listen                  [::]:443 ssl http2;

    # Define Domain Name
    server_name             localhost;
    server_tokens           off;

    # Security Headers
    add_header X-Frame-Options              "SAMEORIGIN";
    add_header X-XSS-Protection             "1; mode=block";
    add_header X-Content-Type-Options       "nosniff";
    add_header Referrer-Policy              "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy      "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'; connect-src https: wss:" always;
    add_header Strict-Transport-Security    "max-age=31536000; includeSubDomains" always;

    # Index Fallback
    index index.html index.htm index.php;

    # Default Charset
    charset utf-8;

    # Redirect Everything to Front-end
    location / {
        proxy_pass                    http://client:8080/;
        proxy_redirect                off;
        proxy_set_header              Host $host;
        proxy_set_header              X-Real-IP $remote_addr;
        proxy_set_header              X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header              X-Forwarded-Host $server_name;
    }

    # Redirect everything after /api/ to Backend
    location /api/ {
        try_files $uri $uri/ public/index.php?$query_string;
    }

    # Handle PHP Files
    location ~ \.php$ {
        fastcgi_pass                  backend:9000;
        fastcgi_index                 index.php;
        fastcgi_buffers               8 16k;
        fastcgi_buffer_size           32k;
        fastcgi_param                 SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_hide_header           X-Powered-By;
        include                       fastcgi_params;
    }

    ###################### Content #########################

    # Deny Access to Files
    location ~ /\.(?!well-known).* {
        deny all;
    }

    # robots.txt
    location = /robots.txt {
        log_not_found off;
        access_log    off;
    }

    ######################## Compression ####################

    # Add global gzip compression to all other files
    gzip                on;
    gzip_comp_level     5;
    gzip_min_length     256;
    gzip_proxied        any;
    gzip_vary           on;
    gzip_types
        application/atom+xml
        application/javascript
        application/json
        application/ld+json
        application/manifest+json
        application/rss+xml
        application/vnd.geo+json
        application/vnd.ms-fontobject
        application/x-font-ttf
        application/x-web-app-manifest+json
        application/xhtml+xml
        application/xml
        font/opentype
        image/bmp
        image/svg+xml
        image/x-icon
        text/cache-manifest
        text/css
        text/plain
        text/vcard
        text/vnd.rim.location.xloc
        text/vtt
        text/x-component
        text/x-cross-domain-policy
        application/octet-stream;

    ######################## SSL ###########################

    # SSL Certificates
    ssl_certificate         conf.d/cert.pem;
    ssl_certificate_key     conf.d/key.pem;

    # SSL Config
    ssl_session_timeout  1d;
    ssl_session_cache    shared:SSL:10m;
    ssl_session_tickets  off;

    # Mozilla Intermediate configuration
    ssl_protocols        TLSv1.2 TLSv1.3;
    ssl_ciphers          ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
}

# Redirect HTTP to HTTPs
server
{
    listen                  80;
    listen                  [::]:80;
    server_name             localhost;

    location / {
        return 301 https://localhost$request_uri;
    }
}
```

# .env As a Blueprint
Before we proceed any further we must adapt the mentality of having our .env file as the true source of configurations, or at least the ones we want to mess with

This will be reflected in the next steps and emphasized upon

# Connecting Everything
First of all, we need to stop our front-end dev server from intercepting anything after /api/ and redirecting the traffic to nginx

We can do that by modifying the `vue.config.js` file or the file that houses your `webpack.config`, if the file doesn't exist simply create it yourself
```javascript
const BundleAnalyzerPlugin = require("webpack-bundle-analyzer")
    .BundleAnalyzerPlugin;

const plugins = [];

plugins.push(new BundleAnalyzerPlugin({ analyzerMode: "disabled" }));

module.exports = {
    devServer: {
        proxy: {
            "^/api": {
                target: "https://webserver/",
                ws: true,
                secure: false
            },
        },
        port: 8081
    },
    configureWebpack: {
        plugins
    },
};
```

next we are going to need to add some variables to our `.env.example` file to use in our docker-compose file and other stuff
```javascript
# Define Application Specific Keys
APP_NAME=Laravel
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_URL=http://localhost

# Log Channel Variables
LOG_CHANNEL=stack
LOG_LEVEL=debug

# Database Variables
DB_CONNECTION=mysql
DB_HOST=database
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=someuser
DB_PASSWORD="lapassord@100"
DB_ROOT_PASSWORD="password@9000"

# Nginx Variables
HTTP_PORT=80:80
HTTPS_PORT=443:443

# BroadCast, Queue, Session Variables
BROADCAST_DRIVER=log
FILESYSTEM_DRIVER=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120

# Cache Variables
CACHE_DRIVER=redis
REDIS_HOST=cache
REDIS_PASSWORD=null
REDIS_PORT=6379

# Mail Variables
MAIL_MAILER=smtp
MAIL_HOST=mailhog
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS=null
MAIL_FROM_NAME="${APP_NAME}"

# Pusher Server Variables
PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=
PUSHER_APP_CLUSTER=mt1
MIX_PUSHER_APP_KEY="${PUSHER_APP_KEY}"
MIX_PUSHER_APP_CLUSTER="${PUSHER_APP_CLUSTER}"
```

create the `docker-compose.yml` file in the root directory and paste in the following content
```javascript
# ! Docker-Compose Specification
version: "3.8"

# ! Define Project Network
networks:
  StackName:

# ? App Stack
services:
  # ? Bring up Nginx After Backend and Link Volumes
  webserver:
    image: nginx:1.19.6-alpine
    container_name: webserver
    restart: unless-stopped
    ports:
      - "${HTTP_PORT}"
      - "${HTTPS_PORT}"
    volumes:
      - ./server/:/etc/nginx/conf.d
    networks:
      - StackName

  # ? Bring up Mysql and configure the Database
  database:
    image: mysql:8.0.21
    container_name: database
    restart: unless-stopped
    tty: true
    expose:
      - "3306"
    environment:
      MYSQL_DATABASE: "${DB_DATABASE}"
      MYSQL_USER: "${DB_USERNAME}"
      MYSQL_PASSWORD: "${DB_PASSWORD}"
      MYSQL_ROOT_PASSWORD: "${DB_ROOT_PASSWORD}"
      SERVICE_TAG: dev
      SERVICE_NAME: database
    volumes:
      - ./storage/database:/var/lib/mysql
    networks:
      - StackName

  # ? Build, Bring up Backend Container
  backend:
    build:
      context: .
      dockerfile: tools/dockerfiles/dev-images/backend.dockerfile
    container_name: backend
    volumes:
      - ./:/var/www/html
      - ./server/config/php.ini:/usr/local/etc/php/php.ini
      - ./server/config/www.conf:/usr/local/etc/php-fpm.d/www.conf
    expose:
      - "9000"
    depends_on:
      - database
      - cache
    networks:
      - StackName

  # ? Bring Up Client UI
  client:
    build:
      context: .
      dockerfile: tools/dockerfiles/dev-images/client.dockerfile
    container_name: client
    volumes:
      - ./client/:/var/www/client
    expose:
      - "8080"
    networks:
      - StackName

  # ? Bring Up Caching Layer
  cache:
    image: redis:6.0.9
    container_name: cache
    expose:
      - "6379"
    networks:
      - StackName

  # * Helper Container for Serving the Front-end
  npm:
    image: node:14
    container_name: npm
    volumes:
      - ./client:/var/www/client
    working_dir: /var/www/client
    entrypoint: ["npm"]
    networks:
      - StackName
```
※Change all instances of `StackName` with your application name

# Create a The init Script
Finally we get to the whole point of this guide, having the user start everything by running a single script which is what we are gonna do here

create `init.sh` file in the root directory of the project, run the following command from the terminal to give it execute permissions
```
$ chmod +x init.sh
```
paste in the following content
```javascript
#!/bin/bash

#?###################################################################################################
#?                                                                                                  #
#?                                      Output Helper Methods                                       #
#?                                                                                                  #
#?###################################################################################################

trap "exit" INT

function blue_text_box()
{
  echo " "
  local s="$*"
  tput setaf 3
  echo " -${s//?/-}-
| ${s//?/ } |
| $(tput setaf 4)$s$(tput setaf 3) |
| ${s//?/ } |
 -${s//?/-}-"
  tput sgr 0
  echo " "
}

function red_text_box()
{
  echo " "
  local s="$*"
  tput setaf 3
  echo " -${s//?/-}-
| ${s//?/ } |
| $(tput setaf 1)$s$(tput setaf 3) |
| ${s//?/ } |
 -${s//?/-}-"
  tput sgr 0
  echo " "
}

function green_text_box()
{
  echo " "
  local s="$*"
  tput setaf 3
  echo " -${s//?/-}-
| ${s//?/ } |
| $(tput setaf 2)$s$(tput setaf 3) |
| ${s//?/ } |
 -${s//?/-}-"
  tput sgr 0
  echo " "
}

#!###################################################################################################
#!                                                                                                  #
#!                                       Script Start                                               #
#!                                                                                                  #
#!###################################################################################################

# ! Add .env file
cp .env.example .env

# ! bring down any service instance if it exists
red_text_box 'Removing Old Stack if It Exists'
docker-compose down

# ? Change Permissions for Artisan
chmod +x artisan

# ? Remove everything in the storage/database & bootstrap/cache directory
sudo rm -rf storage/database/*
sudo rm -rf bootstrap/cache/*.php

# TODO: Start & Build Container Stack
blue_text_box 'Rebuilding the docker images & Starting them'
docker-compose up -d --build

# * Install Laravel Dependencies
green_text_box 'Installing Laravel Dependencies'
docker exec -i backend composer install

# * Install Front-end Dependencies & Build
green_text_box 'Installing Dependencies & Build for User UI'
docker exec -i client npm i
docker exec -i client npm run build

# ! Generate Key & Caching/Optimizing Config
red_text_box 'Generating Laravel'
docker exec -i backend php artisan key:generate


# ! Migrate and Generate Passport Encryption Key
red_text_box 'Migrating & Seeding'
sleep 10
docker exec -i backend composer dump-autoload
docker exec -i backend php artisan migrate:fresh --seed
docker exec -i backend chmod o+w ./storage/ -R
```

# Create The CLI
Lets make interacting the stack easy for developers by creating a simple psuedo-cli

in our `tools/scripts/local` lets create a `cli.sh` file and run
```
$ chmod +x cli.sh
```
paste in the following content or modify the naming scheme to fit your needs by modifying "stack helper instances" and/or changing the container names
```javascript
#!/bin/bash

#?###################################################################################################
#?                                                                                                  #
#?                                      Output Helper Methods                                       #
#?                                                                                                  #
#?###################################################################################################

# ! little helpers for terminal print control and key input
select_option (){
  ESC=$(printf '%b' "\033")

  cursor_blink_on() {
    printf '%s' "$ESC[?25h"
  }

  cursor_blink_off() {
    printf '%s' "$ESC[?25l"
  }

  cursor_to() {
    printf '%s' "$ESC[$1;${2:-1}H"
  }

  print_option() {
    printf '   %s ' "$1"
  }

  print_selected() {
    printf '  %s' "$ESC[7m $1 $ESC[27m"
  }

  get_cursor_row() {
    IFS=';' read -sdR -p $'\E[6n' ROW COL; printf '%s' ${ROW#*[}
  }

  key_input() {
    read -s -n3 key 2>/dev/null >&2
    if [[ $key = $ESC[A ]]; then
      echo up
    fi
    if [[ $key = $ESC[B ]]; then
      echo down
    fi
    if [[ $key = ""  ]]; then
      echo enter
    fi
  }

   # initially print empty new lines (scroll down if at bottom of screen)
   for opt; do
     printf "\n"
   done

   # determine current screen position for overwriting the options
   local lastrow=$(get_cursor_row)
   local startrow=$(($lastrow - $#))

   # ensure cursor and input echoing back on upon a ctrl+c during read -s
   trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
   cursor_blink_off

   local selected=0
   while true; do
     # print options by overwriting the last lines
     local idx=0
     for opt; do
       cursor_to $((startrow + idx))
       if [[ $idx == $selected ]]; then
         print_selected "$opt"
       else
         print_option "$opt"
       fi
       ((idx++))
     done

     # user key control
     case $(key_input) in
       enter) break;;
       up)    ((selected--));
         if (( $selected < 0 )); then selected=$(($# - 1)); fi;;
         down)  ((selected++));
           if (( selected > $# )); then selected=0; fi;;
         esac
       done

       # cursor position back to normal
       cursor_to $lastrow
       printf "\n"
       cursor_blink_on

       return "$selected"
}

#!###################################################################################################
#!                                                                                                  #
#!                                       Script Start                                               #
#!                                                                                                  #
#!###################################################################################################

# Print Instructions
printf '\n> %s\n\n' "$(tput setaf 3)Please Choose your Shell$(tput sgr 0)":

# Options
options=("Bash" "Zsh" "IDK")

select_option "${options[@]}"
choice=$?

index=$choice
value=${options[$choice]}

case $value in 
  Bash)  ## User selected Bash
   shellrc=".bashrc"
   ;;
  Zsh) ## User Selected zsh
   shellrc=".zshrc"
   ;;
  IDK) ## User doesn't know
   shellrc=".bashrc"
   ;;
esac

####################################################################################################

# ? Remove Prexisting CLI Script
sed -n -i '1,/# StackHelper CLI START/p;/# StackHelper CLI END/,$p' $HOME/$shellrc
sed -i '/# StackHelper CLI START/d' $HOME/$shellrc
sed -i '/# StackHelper CLI END/d' $HOME/$shellrc

####################################################################################################

# ? Echo the CLI in the user's .shellrc
echo '
# StackHelper CLI START
# This function serves to integrate
# the dependency-less CLI for 
# Interactive Events Platform

shelper() {
    if [[ $@ == "build" ]]; then
        command docker exec -i client npm run build
    elif [[ $@ == "serve" ]]; then
        command docker-compose run --rm -p "8081:8081" npm run serve
    elif [[ $@ == "install client" || $@ == "i client" ]]; then
        command docker exec -i client npm install
    elif [[ $@ == "install api" || $@ == "i api" ]]; then
        command docker exec -i backend composer install &&
        command docker exec -i backend composer dump-autoload &&
        command docker exec -i backend php artisan key:generate &&
        command docker exec -i backend php artisan migrate:fresh
    elif [[ $@ == "api migrate" ]]; then
        command docker exec -i backend php artisan migrate
    elif [[ $@ == "api seed" ]]; then
        command docker exec -i backend php artisan db:seed
    elif [[ $@ == "api ms" ]]; then
        command docker exec -i backend php artisan migrate:fresh --seed
    elif [[ $@ == "api refresh" ]]; then
        command docker exec -i backend composer dump-autoload &&
        command docker exec -i backend php artisan migrate:fresh --seed
    elif [[ $@ == "stack refresh" || $@ == "stack r" ]]; then
        command docker-compose down && command docker-compose up -d
    elif [[ $@ == "-h" || $@ == "--help" ]]; then
        echo " 
$(tput setaf 3)Stack Helper CLI$(tput sgr 0)

$(tput setaf 3)Usage:$(tput sgr 0)
    shelper [options] [arguments]

$(tput setaf 3)Options:$(tput sgr 0)

-h, --help          Displays this help page

$(tput setaf 3)Arguments:$(tput sgr 0)
    $(tput setaf 2)build$(tput sgr 0)                 Builds the Front-end
    $(tput setaf 1)serve$(tput sgr 0)                 Serves the front-end through port $(tput setaf 5)8081$(tput sgr 0)
    $(tput setaf 3)install client$(tput sgr 0)        Installs the npm Dependencies Shorthand -> $(tput setaf 5)i ui$(tput sgr 0)
    $(tput setaf 3)install api$(tput sgr 0)           Installs Laravel Dependencies, Generate Keys & Migrate DB Shorthand -> $(tput setaf 5)i api$(tput sgr 0)
    $(tput setaf 4)api migrate$(tput sgr 0)           Pushes Laravel Migrations to DB
    $(tput setaf 4)api seed$(tput sgr 0)              Seed the Database
    $(tput setaf 4)api ms$(tput sgr 0)                Migrate & Seed
    $(tput setaf 4)api refresh$(tput sgr 0)           Composer dump-autoload, Migrate & Seed
    $(tput setaf 6)stack refresh$(tput sgr 0)         Refresh the docker stack down/up Shorthand -> $(tput setaf 5)stack r$(tput sgr 0)
"
    else
        echo "
$(tput setaf 1)Please Input a Valid Argument$(tput sgr 0)
OR 
Check the Proper Syntax with
$(tput setaf 3)$ shelper -h$(tput sgr 0)
"
    fi
}

# For Tab-Completion (Basic/Rudimentary)
_shelper_completions()
{
  COMPREPLY+=("build")
  COMPREPLY+=("serve")
  COMPREPLY+=("install")
  COMPREPLY+=("api")
  COMPREPLY+=("stack")
}

complete -F _shelper_completions shelper
# StackHelper CLI END
' >> $HOME/$shellrc
```
Now lets add our cli script execution to the `init.sh` script by adding the following lines to the script file
```javascript
# ! Install CLI
red_text_box 'Installing CLI'
./tools/scripts/local/cli.sh
```
※**Note**: _after installing the pseudo cli you'll need to refresh your shell instance with something like_
```
$ bash
$ zsh
```

# Create The Repo
At this point we're technically done lets create the repo and push it to your favorite repo hosting service (hub,lab,bucket...whatever) run the following command in the project's root directory
```javascript
$ git init
$ git add .
$ git commit -m "First commit or whatever commit message you want"
$ git remote add origin  <REMOTE_URL> 
$ git push origin <main/master/whatever>
```
now anyone clones the project, simply runs
```
$ ./init
```
and he's up and running

# TL;DR
We've successfully create an easy to use development stack that starts up by simply cloning and running ./init.sh, a small pseudo helper cli that helps developers interact with the with the containers

If you understand everything and would just like a repo that has all this instead of going through all this as a learning experience
you can find it [here](https://github.com/viethc/Laravel-Vue-Docker)

if you find any typos or any problems in the process or having some comments about something that you don't like please let me know so that I can fix it or improve upon it, whichever the case may be
