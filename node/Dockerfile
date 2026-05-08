FROM node:20-alpine
RUN apk add --no-cache go
RUN npm install -g pm2
WORKDIR /app
CMD ["pm2-runtime", "ecosystem.config.js"]