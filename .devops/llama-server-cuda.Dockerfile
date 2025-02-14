ARG UBUNTU_VERSION=22.04
ARG CUDA_VERSION=12.2.2
ARG BASE_CUDA_DEV_CONTAINER=nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}
ARG BASE_CUDA_RUN_CONTAINER=nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

# ========== BUILD ==========
FROM ${BASE_CUDA_DEV_CONTAINER} AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        libcurl4-openssl-dev \
        cmake \
        ca-certificates

WORKDIR /app

# Copy your entire repo to /app
COPY . .

# Enable CUDA + cURL
ENV GGML_CUDA=1
ENV LLAMA_CURL=1

# Add CUDA library paths (these are crucial for runtime linking)
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/lib64/stubs:${LD_LIBRARY_PATH}

# Symlink libcuda.so in stubs (good practice, avoids some potential issues)
RUN ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1

# Configure & build with CMake.
RUN cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DLLAMA_CURL=ON \
    -DCMAKE_CUDA_ARCHITECTURES="86;89" \
    -DLLAMA_BUILD_SERVER=ON \
     && \
    cmake --build build --config Release --target llama \
    && \
    cmake --build build --config Release --target llama-server

# **DIAGNOSTIC: List the contents of the build directory and its 'lib' subdirectory**
RUN ls -l /app/build
RUN ls -l /app/build/src

# ========== RUNTIME ==========
FROM ${BASE_CUDA_RUN_CONTAINER} AS runtime

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libgomp1 \
        curl

# Copy the installed binary and library
COPY --from=build /app/build/bin/llama-server /server
COPY --from=build /app/build/src/libllama.so /usr/local/lib/

# Copy CUDA libraries if you need them in runtime - you likely DO
COPY --from=build /usr/local/cuda/lib64 /usr/local/cuda/lib64

ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Expose the port (important for Unraid)
EXPOSE 8000

# Healthcheck (optional)
HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8000/health" ]

# Final entrypoint
ENTRYPOINT [ "/server" ]