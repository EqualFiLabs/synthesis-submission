# Local Deployment Addresses

Last updated: 2026-03-18 (EntryPoint v0.7 migration defaults)

## Network

- RPC: `http://127.0.0.1:8545`
- Chain ID: `31337` (Anvil)

## ERC-4337 (account-abstraction)

- EntryPoint (v0.7, canonical): `0x0000000071727De22Ee835bAF822C1d29692AA4B`
- SimpleAccountFactory (from `account-abstraction` `releases/v0.7`):
  - Read current address from: `../Projects/account-abstraction/deployments/dev/SimpleAccountFactory.json`
- Deterministic Deployment Proxy (Arachnid): `0x4e59b44847b379578588920ca78fbf26c0b4956c`

## ERC-8004 (vanity deployment)

- SAFE Singleton CREATE2 Factory: `0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7`
  - Funding tx: `0xe5f30ce39d02413bd079d689aeafd8c162400ce44e16770b607f7766a31f11a3`
  - Deploy tx: `0x41a6b731f53cf45627c3976abcb9ecd52fb2142f8f6fbbff4e0bb54a9b3667bc`
- MinimalUUPS placeholder: `0xd53dE688e0b0ad436FBdbDa00036832FF6499234`

### Canonical vanity proxies

- IdentityRegistry: `0x8004A818BFB912233c491871b3d84c89A494BD9e`
- ReputationRegistry: `0x8004B663056A597Dffe9eCcC1965A193B7388713`
- ValidationRegistry: `0x8004Cb1BF31DAf7788923b405b754f57acEB4272`

### Current implementations (after owner-impersonated upgrades)

- IdentityRegistry implementation: `0x92b3F652C385C67300e81cD724DDc2Ab43829041`
  - Upgrade tx: `0xf6f5ac83b633228a2614348ac54aa17efb416473349fe4d9862e052306d396f3`
- ReputationRegistry implementation: `0x62a6cEc2fb9248A32FC131B5f65C18Cd6Fc3E327`
  - Upgrade tx: `0x9a4b69bdaadea6ff46e0c93f2a26b272c900109da73e7809f90937d63026cbd4`
- ValidationRegistry implementation: `0xa57fbf0D1717Cebf662Ce17D0A6B4fC59cE063c3`
  - Upgrade tx: `0x1896e361b723f5b4642410a03d29faa5b270455aa3f0c09733e0fb48765342fa`

- Registry owner: `0x547289319C3e6aedB179C0b8e8aF0B5ACd062603`
- Local deployer account used: `0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266`

## ERC-6551 (reference deployment)

- ERC6551Registry (canonical): `0x000000006551c19487814612e58FE06813775758`
  - Deploy tx: `0x76d0744f85ad1d6bd313a5ef58fc923ce377fb69406b8c2a42e383958ecc4c2f`

## Latest DeployV1 broadcast (EqualFi)

- Broadcast file: `EqualFi/broadcast/DeployV1.s.sol/31337/runDeployV1-latest.json`
- Broadcast commit: `064d4be`
- Broadcast timestamp: `2026-03-17T16:32:57Z`
- Transaction count: `77`

### Core outputs

- Diamond: `0x21df544947ba3e8b3c32561399e88b52dc8b2823`
  - CREATE tx: `0x97a4fa0dde7d466975f4554fc25a7953479e5543b289f227ec64703133e3f5f9`
- PositionNFT: `0x2e2ed0cfd3ad2f1d34481277b3204d807ca2f8c2`
  - CREATE tx: `0xa88b26eb3f39041a68333563762c4ef55d5a5e36eb811df657942c3de9fb0166`
- OptionToken: `0xb0f05d25e41fbc2b52013099ed9616f1206ae21b`
  - CREATE tx: `0x170fbd1cfa61e97e1862f9ecbf46d55a6de63382d5d2a430ced672385e11094e`
- ERC-6900 PositionMSCA implementation: `0x976fcd02f7c4773dd89c309fbf55d5923b4c98a1`
  - CREATE tx: `0x3e496ac49192ea2a633d8abbc5dd1af0a9187efabadd7703184e4a2f2af3addd`

## Notes

- `EqualFi/script/DeployERC6551Registry.s.sol` now no-ops successfully because canonical registry code exists at `0x000000006551c19487814612e58FE06813775758`.
- All addresses above were verified on-chain (non-zero bytecode) on local Anvil.
- Legacy reference (no longer the target): EntryPoint v0.6 was `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`.
