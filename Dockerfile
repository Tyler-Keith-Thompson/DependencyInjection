FROM swift:6.1.2

WORKDIR /app

# Copy the package files
COPY Package.swift Package.resolved ./
COPY Sources ./Sources
COPY Tests ./Tests

# First, let's see what's available and try to resolve dependencies
RUN swift package resolve --verbose

# Then try to build and see what actually fails
RUN swift build --verbose
