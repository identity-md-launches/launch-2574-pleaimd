// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title PleaIMD (PLEA)
/// @notice Fixed-supply ERC-20; the deploying address receives the entire supply once.
/// @dev During the IdentityMD launch, msg.sender is the launch factory. There are no admin roles.
contract PleaIMD is ERC20 {
    /// @notice One billion PLEA, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("PleaIMD", "PLEA") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
