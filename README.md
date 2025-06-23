# STXScan – Decentralized Scan-to-Pay Solution

**STXScan** is a decentralized "Scan to Pay" solution that enables seamless, secure cryptocurrency payments via QR codes. It allows users to make fast, peer-to-peer payments using Web3 wallets, removing the need for intermediaries and minimizing transaction fees.

---

## 🚀 Features

* 🔐 **Decentralized Payments**: Operates entirely on Web3, with no central authority or intermediaries.
* 📱 **QR Code Payments**: Instantly generate and scan QR codes to initiate payments.
* 🦊 **Web3 Wallet Support**: Fully compatible with popular wallets like MetaMask, WalletConnect, etc.
* 💸 **Low Fees**: Direct blockchain payments eliminate the fees typically charged by centralized platforms.
* ⛓️ **Cross-Chain Support (Optional)**: Extensible for multi-chain transactions using standards like EIP-681 or Payment Request URIs.
* 📊 **Transaction History**: View and verify past transactions via blockchain explorers.

---

## 📸 How It Works

1. **Merchant** generates a QR code with the payment request details (recipient address, amount, token).
2. **Customer** scans the QR code using their Web3-enabled wallet.
3. Wallet prompts the user to sign and confirm the transaction.
4. The payment is sent directly from the customer's wallet to the merchant's wallet.
5. The merchant can verify transaction status via blockchain or an integrated explorer.

---

## 🛠️ Tech Stack

* **Frontend**: React, TypeScript, Ethers.js/Web3.js
* **Blockchain**: Ethereum / EVM-compatible chains (Polygon, BNB Smart Chain, etc.)
* **Wallet Integration**: MetaMask, WalletConnect
* **QR Code Generator**: `qrcode.react` or `qrcode-generator`
* **Optional Backend**: Node.js (for logging, analytics, or off-chain verification)

---

## 📦 Installation

```bash
git clone https://github.com/yourusername/stxscan.git
cd stxscan
npm install
npm start
```

---

## 🔧 Configuration

Create a `.env` file in the root directory:

```env
REACT_APP_DEFAULT_CHAIN_ID=1
REACT_APP_EXPLORER_BASE=https://etherscan.io/tx/
REACT_APP_WALLET_CONNECT_PROJECT_ID=your_project_id
```

---

## ✅ Usage

### As a Merchant:

1. Open the app and enter the amount and token.
2. Click **Generate QR Code**.
3. Display the QR code to the customer.

### As a Customer:

1. Open your Web3 wallet.
2. Scan the merchant's QR code.
3. Approve the transaction.
4. Done! Funds are sent directly to the merchant.

---

## 🔐 Security Considerations

* All transactions are on-chain and require explicit wallet confirmation.
* QR codes are non-custodial and only contain transaction request data.
* No private keys or sensitive data are stored or handled by STXScan.

---

## 🧪 Testing

To test locally using testnets:

* Configure to use Goerli, Sepolia, or other EVM testnets.
* Load your wallet with test ETH/tokens via a faucet.
* Use testnet block explorers for verification.

---

## 📱 Mobile Wallet Compatibility

STXScan is compatible with:

* MetaMask Mobile
* Trust Wallet
* Rainbow
* Coinbase Wallet
* And all WalletConnect-compatible apps

---

## 🔌 Integrations & APIs

Planned or optional integrations:

* Payment URI support (e.g., `ethereum:0xabc...?value=123`)
* Invoice API (for merchants)
* IPFS/Arweave support for decentralized invoices
* zkSync or Layer 2 support for ultra-low-cost transactions

---

## 🧩 Future Roadmap

* [ ] Support for non-EVM chains (Solana, Bitcoin Lightning)
* [ ] Fiat on-ramp/off-ramp integration
* [ ] Dashboard for merchants
* [ ] NFT/Tokenized receipts
* [ ] Loyalty and rewards features

---

## 📄 License

MIT License. See [LICENSE](./LICENSE) for details.

---

## 🙌 Contributing

We welcome contributions! To contribute:

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Commit your changes: `git commit -am 'Add new feature'`
4. Push to the branch: `git push origin feature/new-feature`
5. Open a pull request

---

## 📬 Contact

For support or business inquiries:

* Email: `contact@stxscan.io`
* Twitter: [@stxscan](https://twitter.com/stxscan)
* Telegram: [t.me/stxscan](https://t.me/stxscan)
