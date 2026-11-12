FROM cubejs/cube:latest

WORKDIR /cube/conf

# Copy configuration and semantic data models
COPY cube.js ./
COPY model/ ./model/

EXPOSE 4000

CMD ["cubejs", "server"]
