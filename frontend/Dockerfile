FROM nginx:stable-alpine
COPY ./dist /usr/share/nginx/html

# Ensure nginx listens on the Cloud Run expected port (8080)
RUN sed -i 's/listen\s\+80;/listen 8080;/' /etc/nginx/conf.d/default.conf || true
EXPOSE 8080
CMD ["/usr/sbin/nginx", "-g", "daemon off;"]
