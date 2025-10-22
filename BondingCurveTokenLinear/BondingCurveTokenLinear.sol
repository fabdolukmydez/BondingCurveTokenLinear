// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./MinimalERC20.sol";

/// @title BondingCurveTokenLinear
/// @notice ERC20 token with a linear bonding curve: price = a * supply + b
contract BondingCurveTokenLinear is MinimalERC20 {
    uint256 public a; // slope (wei per token)
    uint256 public b; // base price (wei)
    address public owner;
    event Bought(address indexed buyer, uint256 tokens, uint256 cost);
    event Sold(address indexed seller, uint256 tokens, uint256 proceeds);

    constructor(uint256 _a, uint256 _b) MinimalERC20("BondingLinear", "BCL") {
        a = _a;
        b = _b;
        owner = msg.sender;
    }

    // price to mint n tokens = integral from S to S+n of (a*x + b) dx
    function priceToMint(uint256 n) public view returns (uint256) {
        uint256 S = totalSupply;
        // integral: a/2 * ((S+n)^2 - S^2) + b * n
        uint256 term1 = a * ((S + n) * (S + n) - S * S) / 2;
        uint256 term2 = b * n;
        return term1 + term2;
    }

    // buy tokens by sending ETH (payable)
    function buy() external payable {
        require(msg.value > 0, "no value");
        // binary search how many tokens can be bought for msg.value
        uint256 low = 1;
        uint256 high = 1;
        // find an upper bound
        while(priceToMint(high) <= msg.value) {
            high *= 2;
        }
        // binary search
        uint256 best = 0;
        while(low <= high) {
            uint256 mid = (low + high) / 2;
            uint256 cost = priceToMint(mid);
            if(cost <= msg.value) {
                best = mid;
                low = mid + 1;
            } else {
                if(mid == 0) break;
                high = mid - 1;
            }
        }
        require(best > 0, "insufficient value");
        uint256 cost = priceToMint(best);
        _mint(msg.sender, best * (10 ** decimals));
        // refund excess
        if(msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
        emit Bought(msg.sender, best, cost);
    }

    // sell tokens back: user must approve this contract to transfer tokens
    function sell(uint256 tokenAmount) external {
        require(tokenAmount > 0, "zero");
        // tokenAmount is in whole tokens (not 10^decimals)
        uint256 S = totalSupply;
        require(balanceOf[msg.sender] >= tokenAmount * (10 ** decimals), "insufficient balance");
        // proceeds = integral from S-tokenAmount to S of price(x) dx
        uint256 s0 = S - tokenAmount;
        uint256 term1 = a * (S * S - s0 * s0) / 2;
        uint256 term2 = b * tokenAmount;
        uint256 proceeds = term1 + term2;
        _burn(msg.sender, tokenAmount * (10 ** decimals));
        payable(msg.sender).transfer(proceeds);
        emit Sold(msg.sender, tokenAmount, proceeds);
    }

    receive() external payable {}
}
