FROM node:20-alpine
LABEL description="LabOps API — lightweight VM management and health check server"
RUN apk add --no-cache curl git bash
WORKDIR /app
COPY server.js .
EXPOSE 3000
CMD ["node", "server.js"]
