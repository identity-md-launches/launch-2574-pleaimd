# PleaIMD (PLEA)

PleaIMD is an immutable ERC-20 with a fixed supply of **1,000,000,000 PLEA** and
**18 decimals**. Its constructor mints the entire supply to its immediate caller
(`msg.sender`) in one mint. On the IdentityMD launch, that caller is the factory.

| Deployment parameter | Value |
| --- | --- |
| Source and Solidity identifier | `src/PleaIMD.sol:PleaIMD` |
| Token name | `PleaIMD` |
| Token symbol | `PLEA` |
| Decimals | `18` |
| Total supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | Immediate deploying address; the factory for this launch |
| Launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimization | Enabled, 200 runs |
| Metadata hash | `none` |

## Design and assumptions

The only custom behavior is the mint in `PleaIMD`'s constructor, with the amount
declared as `INITIAL_SUPPLY`. ERC-20 accounting and metadata use the vendored
OpenZeppelin Contracts v5.1.0 implementation without overrides. The constructor
does not call external contracts and can deploy on an empty chain. There are no
linked libraries, application contracts, initialization calls, or proxy.

Transfers deliver exactly the requested amount. There are no transfer taxes,
fees, burns, rebases, trading gates, time limits, or special address exemptions.
The runtime exposes no additional mint, burn, pause, blacklist, seizure,
ownership, or upgrade functions. The deployer has only the same balance and
allowance rights as every other holder after deployment. No administrative
owner is needed.

Standard ERC-20 behavior includes:

- Successful `transfer`, `approve`, and `transferFrom` calls return `true`.
  Invalid calls revert with OpenZeppelin's ERC-6093 custom errors.
- Zero-value transfers to a valid address are allowed and emit `Transfer`.
  Transfers to the zero address are rejected, including zero-value transfers.
- `approve` replaces the allowance; approving zero revokes it. A zero-address
  spender is rejected. Approval does not reserve tokens or require a balance.
- `transferFrom` requires the caller's allowance even when caller and sender
  are the same address. Finite allowances decrease on spending; a maximum
  `uint256` allowance remains unchanged until the holder replaces it.
- Explicit approvals emit `Approval`; spending an allowance does not emit a
  second `Approval` event in this OpenZeppelin version. Indexers should query
  `allowance` for its current value.
- Failed transfers revert all changes, including attempted allowance spending.
  Ordinary self-transfers preserve balances.

## Build and test

With Foundry and Solidity 0.8.26 installed, run from the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xdd3ba4f728c6a1f8df7475fcf11aa1f8a636f97f04c1e63ae1b91efa8f1571c8 forge test
forge fmt --check
```

All Solidity dependencies are ordinary files under `lib/`. Builds and tests
need no network, fork, RPC endpoint, private key, or environment configuration.
The optional command-level fuzz seed above matches the verifier. Tests do not
read or mutate environment variables. `foundry.toml` sets 1,024 cases for each
fuzz test and 128 invariant runs of 64 calls each, with unexpected handler
reverts treated as failures. These testing limits are not contract parameters.

- `test/PleaIMD.t.sol` checks metadata, the single mint event, arbitrary
  deployers, exact and zero transfers, self-transfers, approvals, allowance
  revocation and isolation, infinite allowances, insufficient balances and
  allowances, failure atomicity, and the absence of administrative entry points.
- `test/PleaIMDLaunch.t.sol` checks CREATE2 factory deployment, exact 10%/80%/10%
  distribution, claims and pool-facing transfers, runtime size, and prohibited
  runtime opcodes. Its factory and pool addresses are local test fixtures; it
  does not execute a Uniswap pool or simulate prices.
- `test/PleaIMD.invariant.t.sol` compares balances and allowances with an
  independent model across randomized sequences of transfers, approvals,
  revocations, and delegated spending. It verifies conservation of the entire
  supply and exact allowance accounting, including self-transfers.

The supplied protected tests were read as acceptance specifications. Their
complete launcher, owner-check harness, and Uniswap dependencies are not part
of this input, so those external integration tests are run by the network's
verifier, not claimed as local results. Slither and Mythril were not run.

## Deployment and operational responsibilities

Deploy the creation bytecode produced for `src/PleaIMD.sol:PleaIMD`, with no
constructor arguments and no ETH. Deploy directly through the intended launch
factory: introducing an intermediate deployer would give that intermediate
contract the entire supply. A direct EOA deployment would instead give the EOA
the supply. No token recipient address is hardcoded or supplied separately.

The network prepares its launch manifest and deploys the token. This repository
does not contain a launch manifest or broadcast script. The factory is
responsible for distribution and liquidity; none of those amounts move during
the token constructor. The provided launch terms allocate 10% to the swarm
distributor, 80% to the pool, and 10% to the requester remainder address.

For the separate manifest step, the supplied launch terms are:

| Launch setting | Supplied value |
| --- | --- |
| Pair token (IMD, 18 decimals) | `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Pool fee | `12500` (1.25%; a pool fee, not a token transfer fee) |
| Tick spacing | `60` |
| Initial price provenance | `79228162514264337593543950336` |
| `economics.poolBps` | `8000` |
| `economics.initialMarketCapWei` | `5000000000000000000000` (5,000 IMD) |
| `economics.remainderTo` | `0xbb85c1b7540d9e7b56f7a595fc1ff7dd07cb0823` |

These are launch inputs, not token constructor arguments. The deployer derives
the actual pool opening price from the market cap, supply, and currency ordering.
The token requires no router, oracle, distributor, or pool address and treats all
nonzero transfer recipients alike.

### After launch

There are no owner settings, keepers, or routine administrative actions. The
network deployer is responsible for verifying the deployed source and compiler
settings, checking metadata and the constructor mint event, and confirming the
factory's distribution and pool operations. Independent adversarial review and
the protected integration checks remain part of the network's release process;
local tests alone are not a security audit.

Holders manage their own balances and approvals. Use approvals appropriate to
the intended spending; maximum approvals permit future spending until revoked.
When replacing a nonzero allowance, applications should consider first setting
it to zero and waiting for confirmation to mitigate the standard ERC-20
allowance replacement race. Tokens sent to the token contract itself or to a
contract unable to return them cannot be recovered by an administrator. Native
ETH is not accepted through ordinary calls, and there is no asset-rescue role.

## Dependencies

`lib/openzeppelin-contracts` contains the six original v5.1.0 files needed for
ERC-20 plus its licensing (five Solidity files and `LICENSE`). `lib/forge-std`
contains v1.9.7's `src/` tree and its MIT/Apache licenses for testing. Files are
vendored without changes or submodules. `DEPENDENCIES.json` records source URLs,
release tags, archive SHA-256 hashes, and per-file hashes. No installation step
is required during offline verification.
