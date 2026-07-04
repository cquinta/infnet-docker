# Python FastAPI Application Example

This is a simple example of a Python application using the FastAPI framework, containerized with Docker.

## Description

The application provides a single endpoint `/` that returns a "Hello World" JSON message.

This project includes multiple Dockerfiles to demonstrate different containerization approaches:

*   `Dockerfile`: A straightforward Dockerfile that sets up the environment, installs dependencies, and runs the application.
*   `Dockerfile.stages`: A multi-stage Dockerfile that first builds a virtual environment with the dependencies in a `builder` stage, then copies it to a smaller final image. This is a best practice for creating optimized and more secure Docker images.

## How to Run with Docker

### Prerequisites

*   [Docker](https://docs.docker.com/get-docker/) installed.

### Building the Image

You can choose which Dockerfile to use.

**Using `Dockerfile`:**

```bash
docker build -t python-app .
```

**Using `Dockerfile.stages`:**

```bash
docker build -t python-app-staged -f Dockerfile.stages .
```

### Running the Container

After building the image, run the container:

```bash
docker run -d -p 8000:8000 --name my-python-app python-app
```

Or, if you used the staged build:

```bash
docker run -d -p 8000:8000 --name my-python-app python-app-staged
```

### Accessing the Application

Once the container is running, you can access the application at [http://localhost:8000](http://localhost:8000) in your web browser or using a tool like `curl`:

```bash
curl http://localhost:8000
```

You should see the output:

```json
{"message":"Hello World"}
```

## Local Development

The `start.sh` script is provided for local development. It creates a Python virtual environment, installs the dependencies from `requirements.txt`, and runs the application with `uvicorn` in reload mode.

**Note:** The script is intended for a Unix-like environment (Linux, macOS).

To run it:

```bash
bash start.sh
```

## Files

*   `main.py`: The main application file containing the FastAPI code.
*   `requirements.txt`: Lists the Python dependencies for the project.
*   `Dockerfile`: A standard Dockerfile for building the application image.
*   `Dockerfile.stages`: A multi-stage Dockerfile for an optimized build.
*   `start.sh`: A shell script for setting up and running the application locally.
*   `.dockerignore`: Specifies which files and directories to exclude from the Docker build context.
