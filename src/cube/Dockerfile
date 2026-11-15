ARG CUBEJS_VERSION=v0.36.0
FROM cubejs/cube:${CUBEJS_VERSION}

WORKDIR /cube/conf

# Copy configuration and semantic data models
COPY cube.js ./
COPY model/ ./model/

EXPOSE 4000

CMD ["cubejs", "server"]
