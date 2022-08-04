// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

import "hardhat/console.sol";
import "../IRouterV2.sol";
import "../Tokens/IBEP20.sol";
import "../Tokens/BEP20.sol";
import "../Libraries/SafeBEP20.sol";

contract RouterMock {
    using SafeBEP20 for IBEP20;

    // Needs to be set up with the proper tokens for transfer them.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual returns (uint256[] memory amounts) {
        IBEP20 token = IBEP20(path[1]);
        token.safeTransfer(to, amountIn);

        amounts = new uint256[](1);
        amounts[0] = amountIn;
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        IBEP20 token = IBEP20(path[1]);
        token.safeTransfer(to, amountOutMin);

        amounts = new uint256[](1);
        amounts[0] = amountOutMin;
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }

    // Returns always 2.5 each token
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        amountA = 1e18;
        amountB = 1e18;
        BEP20(tokenA).transfer(msg.sender, amountA);
        BEP20(tokenB).transfer(msg.sender, amountB);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        amountA = 1e18;
        amountB = 1e18;
    }
}
