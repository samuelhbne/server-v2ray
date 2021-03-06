server {
  listen NGPORT;
  listen [::]:NGPORT;
  server_name           NGDOMAIN;
    location WSPATH {
      if ($http_upgrade != "websocket") {
          return 404;
      }
      proxy_redirect off;
      proxy_pass http://127.0.0.1:VPORT;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}