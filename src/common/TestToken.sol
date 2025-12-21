// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

/// @title TestToken
/// @notice Test ERC20 token for local development and testing
/// @dev Uses 16 decimals to match BZZ/sBZZ token specification
contract TestToken is ERC20, OwnableRoles {
    uint256 public constant MINTER_ROLE = 1 << 0;

    constructor() {
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, MINTER_ROLE);
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    function name() public pure override returns (string memory) {
        return "Swarm Token";
    }

    function symbol() public pure override returns (string memory) {
        return "sBZZ";
    }

    /// @dev BZZ/sBZZ uses 16 decimals instead of the standard 18
    function decimals() public pure override returns (uint8) {
        return 16;
    }

    /// @notice Mints tokens to a specified address
    /// @dev Requires MINTER_ROLE or owner
    function mint(address to, uint256 amount) external onlyOwnerOrRoles(MINTER_ROLE) {
        _mint(to, amount);
    }
}
