### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Cast

```shell
$ cast <subcommand>
```

### Import wallet

```shell
cast wallet import <your-wallet-name> --private-key YOUR_PRIVATE_KEY_HERE
```

```shell
cast wallet list
```

### Deploy

```shell
$ forge script script/Pickr.s.sol:DeployPickrScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

```shell
forge script script/Pickr.s.sol \
  --rpc-url https://sepolia.base.org/ \
  --broadcast \
  --account third
```

### Verify contract

```shell
forge verify-contract \
  <your-deployed-contract> \
  src/Pickr.sol:Pickr \
  --chain 84532 \
  --verifier sourcify \
  --constructor-args $(cast abi-encode "constructor(address)" $(cast wallet address --account third))
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
