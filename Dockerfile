FROM node:18 AS builder

WORKDIR /app
COPY package*.json pnpm-lock.yaml prisma ./

RUN yarn global add pnpm
RUN pnpm install

COPY . .
RUN yarn build

FROM node:18

RUN yarn global add pnpm

WORKDIR /app

COPY --from=builder /app/node_modules node_modules
COPY --from=builder /app/dist dist
COPY --from=builder /app/package.json ./

ENTRYPOINT pnpm start