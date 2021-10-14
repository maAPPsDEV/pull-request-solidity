// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.3;

import "@openzeppelin/contracts/utils/Arrays.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";

/**
 * @title Helper functions
 */
library MathLib {
  using Arrays for uint256[];
  using Babylonian for uint256;

  /**
   * @dev Calculates the optimal amount of assets to swap
   * in order to supply to AMM in the exact proportionate.
   *
   * In order to preserve the calculation precision as much as possible,
   * fee must be provided as an integer value,
   * and in where extension represents the value used to extend fee.
   * i.e. If the fee of an AMM is 0.003%, fee and extension can be
   * 3 and 1000, or 300 and 1e5.
   * The bigger extended, the more precise result is out,
   * but the more intensive computation is required.
   *
   * The biggest computation here is sqrt at the end.
   * The bigger parameters get in, the more intensive computation is required.
   *
   * It assumes one-side swap, so, swap direction may be reversed as B to A
   * depending on the AMM pool's ratio and the amount to swap.
   * It reverts depending on arithmetic Overflow/Underflow,
   * and any violation to the requirements.
   *
   * @param amountA   - The amount of asset A to be supplied to AMM. It can be 0, but amountA and amountB cannot be 0 at the same time.
   * @param amountB   - The amount of asset B to be supplied to AMM. It can be 0, but amountA and amountB cannot be 0 at the same time.
   * @param reserveA  - The reserved amount of asset A in the AMM pool. It cannot be 0.
   * @param reserveB  - The reserved amount of asset B in the AMM pool. It cannot be 0.
   * @param fee       - The swap fee in the AMM pool, but it must be extended value to be an integer.
   * @param extension - The value used to extend the swap fee.
   *
   * @return
   * reversed   - Indicates that the swap direction should be reversed as B to A.
   * swapAmount - The amount of asset A or B to swap.
   */
  function getOptimalSwapAmount(
    uint256 amountA,
    uint256 amountB,
    uint256 reserveA,
    uint256 reserveB,
    uint256 fee,
    uint256 extension
  ) internal pure returns (bool reversed, uint256 swapAmount) {
    require(
      extension > fee && reserveA > 0 && reserveB > 0,
      "OLib: Invalid Parameter"
    );
    require(amountA > 0 || amountB > 0, "OLib: Invalid Amount");

    uint256 net; // 1 - fee

    if (amountB != 0 && reserveA * amountB > reserveB * amountA) {
      // reverse the swap direction, if the asset ratio is greater than AMM pool ratio
      (amountA, amountB, reserveA, reserveB) = (
        amountB,
        amountA,
        reserveB,
        reserveA
      );
      reversed = true;
    }

    unchecked {
      // never underflow
      net = extension - fee;
    }

    uint256 k = reserveA * reserveB;
    uint256 a = (amountB + reserveB) * net;
    uint256 b = (extension + net) * (k + reserveA * amountB);

    // split c component into two parties, in order to keep in the unsigned operation
    uint256 c1 = amountB * reserveA * reserveA;
    uint256 c2 = amountA * k;

    // calculate quadratic component, depening on the sign of c component
    uint256 quadratic;
    if (c1 >= c2) {
      quadratic = b * b - 4 * a * (c1 - c2) * extension;
    } else {
      quadratic = b * b + 4 * a * (c2 - c1) * extension;
    }

    // sqrt is intensive depending on the size of value
    swapAmount = (quadratic.sqrt() - b) / (2 * a);
  }
}
