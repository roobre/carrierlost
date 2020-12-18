FROM alpine:edge as hugo

RUN apk add hugo
COPY . .
RUN hugo -Dv

FROM nginx:alpine
COPY --from=hugo /public /usr/share/nginx/html
RUN chown -R nginx:nginx /usr/share/nginx/html
