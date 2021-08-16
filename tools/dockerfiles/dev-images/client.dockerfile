# ! Image
FROM node:14-alpine

# ? Set Working Directory
WORKDIR /var/www/client

# * Install PM2 to serve the app
RUN npm install pm2 -g

# ? Serve the application on start
CMD command pm2 serve ./dist/ 8080 --spa --watch && pm2 log