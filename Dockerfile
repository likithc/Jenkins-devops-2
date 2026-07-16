# Stage 1: Build & Dependencies
FROM node:20-alpine AS build
WORKDIR /app

# Copy package files first to leverage Docker layer caching
COPY package*.json ./

# Install all dependencies (including devDependencies for testing)
RUN npm ci

# Copy the rest of the application source code
COPY . .

# Stage 2: Production Image
FROM node:20-alpine AS production

# Security: Create and use a non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy only production dependencies and compiled/source files from the build stage
COPY --from=build --chown=appuser:appgroup /app/package*.json ./
# For a raw Node.js app, we can just run a production install here to minimize size, 
# or if it was transpiled (e.g., TS), we would copy the dist folder.
RUN npm ci --only=production && npm cache clean --force

COPY --from=build --chown=appuser:appgroup /app/ ./

# Switch to the non-root user
USER appuser

EXPOSE 3000

CMD ["npm", "start"]
