FROM alpine:edge as hugo

RUN apk add hugo
WORKDIR /blog
COPY . .
RUN hugo -Dv

FROM nginx:alpine
COPY --from=hugo /blog/public /usr/share/nginx/html
RUN chown -R nginx:nginx /usr/share/nginx/html
