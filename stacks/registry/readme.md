# Example usage

# if you want to use previous build layers as cache
# docker pull registry.example.com/repo/image_name:latest

docker-compose build

docker tag image_name:latest registry.example.com.com/repo/image_name:someversion

docker push registry.example.com/repo/image_name
