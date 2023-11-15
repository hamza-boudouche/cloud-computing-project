sudo snap install docker
sudo systemctl start snap.docker.dockerd
sudo docker run -e FRONTEND_ADDR=${frontend_ip} gcr.io/google-s:waamples/microservices-demo/loadgenerator:v0.8.1
