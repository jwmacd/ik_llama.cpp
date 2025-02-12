ARG UBUNTU_VERSION=22.04
ARG CUDA_VERSION=11.7.1
ARG BASE_CUDA_DEV_CONTAINER=nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}
ARG BASE_CUDA_RUN_CONTAINER=nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

# ========== STAGE 1: BUILD ==========
FROM ${BASE_CUDA_DEV_CONTAINER} AS build

RUN apt-get update && \
    apt-get install -y \
        build-essential \
        git \
        libcurl4-openssl-dev \
        cmake

WORKDIR /app

# Copy your entire repo to /app
COPY . .

# Enable CUDA + cURL
ENV GGML_CUDA=1
ENV LLAMA_CURL=1

# Add CUDA library paths
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/lib64/stubs:${LD_LIBRARY_PATH}

# Symlink libcuda.so in stubs
RUN ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1

# Configure & build with CMake
RUN cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DLLAMA_CURL=ON \
    -DCMAKE_CUDA_ARCHITECTURES="52;61;70;75" \
    -DCMAKE_EXE_LINKER_FLAGS="-L/usr/local/cuda/lib64/stubs -lcuda" \
    -DCMAKE_LIBRARY_PATH=/usr/local/cuda/lib64/stubs && \
    cmake --build build --config Release

# ========== STAGE 2: RUNTIME ==========
FROM ${BASE_CUDA_RUN_CONTAINER} AS runtime

RUN apt-get update && \
    apt-get install -y \
        libcurl4-openssl-dev \
        libgomp1 \
        curl

# Copy the compiled llama-server binary
COPY --from=build /app/build/bin/llama-server /server

# Copy CUDA libraries if you need them in runtime
COPY --from=build /usr/local/cuda/lib64 /usr/local/cuda/lib64

ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Healthcheck (optional)
HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8080/health" ]

# Final entrypoint
ENTRYPOINT [ "/server" ]
