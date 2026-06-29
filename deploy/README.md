# VPN 节点部署脚本说明

本目录只用于 VPN 节点服务器部署，不用于部署主服务器后台、MySQL 或管理后台前端。

主服务器部署方式：

- `server/`：放到宝塔面板 Node.js 项目中运行。
- `admin-web/`：构建后放到宝塔面板网站目录。
- MySQL：在宝塔面板中创建 `magic` 数据库和 `magic` 用户。

VPN 节点服务器用于真实转发用户流量，建议单独购买 VPS，不要和主服务器共用公网 IP。

目录内容：

- `install-node-from-github.sh`：一键从 GitHub 拉取项目并部署节点。
- `install-centos9.sh`：初始化 CentOS 9 节点服务器，安装 WireGuard、基础工具、防火墙规则。
- `node.env.example`：节点配置示例。
- `setup-wireguard-node.sh`：生成 WireGuard 密钥并创建 `wg0` 配置。
- `magic-node-status.sh`：查看节点状态、IP 转发、防火墙和 WireGuard 状态。

建议部署结构：

```text
/opt/magic-vpn-node/
  deploy/
  config/
    node.env
```

## 推荐：一键部署节点

把本项目上传到 GitHub 后，在节点服务器执行一条命令即可。

示例：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/你的仓库/main/deploy/install-node-from-github.sh | sudo bash -s -- \
  --repo https://github.com/你的用户名/你的仓库.git
```

脚本会自动识别：

- 公网 IP
- 国家代码
- 城市
- 大区
- 节点名称

如果你想手动覆盖，也可以加参数：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/你的仓库/main/deploy/install-node-from-github.sh | sudo bash -s -- \
  --repo https://github.com/你的用户名/你的仓库.git \
  --name hk-01 \
  --country HK \
  --city HongKong \
  --region asia
```

部署完成后，终端会输出：

```text
---------------- MAGIC_NODE_CONFIG_START ----------------
{
  "name": "jp-tokyo-01",
  "region": "asia",
  "country_code": "JP",
  "city": "Tokyo",
  "public_ip": "1.2.3.4",
  "endpoint_host": "1.2.3.4",
  "endpoint_port": 51820,
  "wg_public_key": "xxxxx",
  "bandwidth_limit_bps": null,
  "current_load": 0,
  "status": "maintenance",
  "allow_free_trial": false
}
----------------- MAGIC_NODE_CONFIG_END -----------------
```

复制中间这段 JSON，到管理后台 `节点管理` 页面，粘贴到“粘贴节点部署配置”，点击“导入配置”，再点击“新增节点”即可。

## 手动部署节点

```bash
cd /opt/magic-vpn-node/deploy
sudo bash install-centos9.sh
sudo cp node.env.example /opt/magic-vpn-node/config/node.env
sudo vim /opt/magic-vpn-node/config/node.env
sudo bash setup-wireguard-node.sh
sudo bash magic-node-status.sh
```

注意：

- 一键脚本默认安装到 `/opt/magic-vpn-node`。
- 节点部署完成后的可粘贴配置会保存到 `/opt/magic-vpn-node/node-config.json`。
- `NODE_ID`、`NODE_TOKEN`、`CONTROL_API_URL` 后续应由主服务器管理后台生成。
- 节点只开放 WireGuard UDP 端口，默认 `51820/udp`。
- 不要在节点服务器上部署 MySQL、管理后台或支付回调。
- 节点的 WireGuard 私钥只保存在节点本机，不上传到主服务器。
- 生产环境需要配套节点 Agent，定时向主服务器上报心跳和流量。
