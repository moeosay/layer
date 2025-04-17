#!/bin/bash

# 读取交互输入
read -p "Enter container name (e.g., vlayer01): " CONTAINER_NAME
read -p "Enter JWT API Token: " JWT_TOKEN
read -p "Enter Private Key (starts with 0x): " PRIVATE_KEY
read -p "Enter Git username: " GIT_USER
read -p "Enter Git email: " GIT_EMAIL

# 创建初始化脚本目录
mkdir -p containers/$CONTAINER_NAME

# 写入容器初始化脚本
cat <<EOF > containers/$CONTAINER_NAME/init.sh
#!/bin/bash
set -e

echo "🕒 Setting timezone to America/Los_Angeles..."
apt update && apt install -y curl git unzip wget sudo nano cron tzdata
ln -fs /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

echo "🔧 Installing Foundry..."
curl -L https://foundry.paradigm.xyz | bash
source /root/.bashrc && foundryup

echo "🍞 Installing Bun..."
curl -fsSL https://bun.sh/install | bash
source /root/.bashrc

echo "🔗 Installing vlayer..."
curl -SL https://install.vlayer.xyz | bash
source /root/.bashrc && vlayerup

echo "🔐 Git setup"
git config --global user.name "$GIT_USER"
git config --global user.email "$GIT_EMAIL"

echo "📁 Initializing projects..."
mkdir -p /app && cd /app
vlayer init simple-time-travel --template simple-time-travel
vlayer init simple-teleport --template simple-teleport
vlayer init simple-web-proof --template simple-web-proof
vlayer init simple-email-proof --template simple-email-proof

echo "📝 Creating .env files..."
cat <<EOT > /app/simple-time-travel/vlayer/.env.testnet.local
VLAYER_API_TOKEN=$JWT_TOKEN
EXAMPLES_TEST_PRIVATE_KEY=$PRIVATE_KEY
CHAIN_NAME=optimismSepolia
JSON_RPC_URL=https://sepolia.optimism.io
EOT

cp /app/simple-time-travel/vlayer/.env.testnet.local /app/simple-teleport/vlayer/
cp /app/simple-time-travel/vlayer/.env.testnet.local /app/simple-web-proof/vlayer/
cp /app/simple-time-travel/vlayer/.env.testnet.local /app/simple-email-proof/vlayer/

echo "🚀 Running initial round..."
cd /app/simple-time-travel && forge build && cd vlayer && bun install && bun run prove:testnet
cd /app/simple-teleport && forge build && cd vlayer && bun install && bun run prove:testnet
cd /app/simple-web-proof && forge build && cd vlayer && bun install && bun run prove:testnet
cd /app/simple-email-proof && forge build && cd vlayer && bun install && bun run prove:testnet

echo "📜 Creating /app/run-all.sh..."
cat <<'EOS' > /app/run-all.sh
#!/bin/bash
set -e
export PATH="/root/.foundry/bin:/root/.bun/bin:$PATH"

echo "🔁 [$(date)] Starting batch run..." >> /var/log/vlayer-cron.log

cd /app/simple-time-travel/vlayer && bun run prove:testnet
cd /app/simple-teleport/vlayer && bun run prove:testnet
cd /app/simple-web-proof/vlayer && bun run prove:testnet
cd /app/simple-email-proof/vlayer && bun run prove:testnet

echo "✅ [$(date)] All tasks completed." >> /var/log/vlayer-cron.log
EOS
chmod +x /app/run-all.sh

echo "🕒 Setting up cron every 58 minutes..."
echo "*/58 * * * * /app/run-all.sh >> /var/log/vlayer-cron.log 2>&1" | crontab -
service cron start

echo "🌐 Internal container IP:"
ip addr show eth0 | grep "inet " | awk '{print \$2}' | cut -d/ -f1
EOF

chmod +x containers/$CONTAINER_NAME/init.sh

# 创建并挂载容器
docker run -dit \
  --name $CONTAINER_NAME \
  -e ALL_PROXY=$ALL_PROXY \
  -e HTTP_PROXY=$ALL_PROXY \
  -e HTTPS_PROXY=$ALL_PROXY \
  -v $(pwd)/containers/$CONTAINER_NAME:/root \
  ubuntu:24.04 bash

# 自动执行容器内脚本
docker exec -it $CONTAINER_NAME bash /root/init.sh

echo "🌐 Container external IP (via proxy or direct):"
curl -s ifconfig.me && echo
