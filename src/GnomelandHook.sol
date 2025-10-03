// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title GnomelandHook
 * @notice Uniswap V4 hook that collects fees from GNOME/ETH swaps and forwards them to NFT contract
 * @dev Implements afterSwap hook to collect a portion of swap volume as fees
 */
contract GnomelandHook is 
    BaseHook, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable 
{
    using PoolIdLibrary for PoolKey;

    // NFT contract that receives collected fees
    address public nftContract;
    
    // Fee percentage in basis points (100 = 1%)
    uint256 public feePercentage;
    
    // Accumulated fees ready to be sent to NFT contract
    uint256 public accumulatedFees;
    
    // Minimum amount before triggering auto-transfer to NFT contract
    uint256 public autoTransferThreshold;
    
    event FeesCollected(address indexed pool, uint256 amount);
    event FeesForwarded(address indexed nftContract, uint256 amount);
    event NFTContractUpdated(address indexed oldContract, address indexed newContract);
    event FeePercentageUpdated(uint256 oldPercentage, uint256 newPercentage);
    event AutoTransferThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        _disableInitializers();
    }

    /**
     * @notice Initialize the hook contract
     * @param _nftContract Address of the NFT contract to receive fees
     * @param _feePercentage Initial fee percentage (in basis points)
     * @param _autoTransferThreshold Minimum ETH to trigger auto-transfer
     */
    function initialize(
        address _nftContract,
        uint256 _feePercentage,
        uint256 _autoTransferThreshold
    ) external initializer {
        require(_nftContract != address(0), "Invalid NFT contract");
        require(_feePercentage <= 1000, "Fee too high"); // Max 10%
        
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        nftContract = _nftContract;
        feePercentage = _feePercentage;
        autoTransferThreshold = _autoTransferThreshold;
    }

    /**
     * @notice Returns the hook permissions
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Hook called after each swap
     * @dev Collects fees and forwards to NFT contract if threshold is met
     */
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        // Calculate fee based on swap volume
        uint256 swapAmount = params.amountSpecified > 0 
            ? uint256(params.amountSpecified) 
            : uint256(-params.amountSpecified);
        
        uint256 feeAmount = (swapAmount * feePercentage) / 10000;
        
        if (feeAmount > 0) {
            accumulatedFees += feeAmount;
            emit FeesCollected(address(uint160(uint256(PoolId.unwrap(key.toId())))), feeAmount);
            
            // Auto-forward if threshold is met
            if (accumulatedFees >= autoTransferThreshold) {
                _forwardFees();
            }
        }
        
        return (BaseHook.afterSwap.selector, 0);
    }

    /**
     * @notice Manually trigger fee forwarding to NFT contract
     */
    function forwardFees() external nonReentrant {
        _forwardFees();
    }

    /**
     * @dev Internal function to forward accumulated fees to NFT contract
     */
    function _forwardFees() internal {
        uint256 amount = accumulatedFees;
        require(amount > 0, "No fees to forward");
        
        accumulatedFees = 0;
        
        (bool success, ) = nftContract.call{value: amount}("");
        require(success, "Fee transfer failed");
        
        emit FeesForwarded(nftContract, amount);
    }

    /**
     * @notice Update the NFT contract address
     * @param _nftContract New NFT contract address
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        require(_nftContract != address(0), "Invalid address");
        address oldContract = nftContract;
        nftContract = _nftContract;
        emit NFTContractUpdated(oldContract, _nftContract);
    }

    /**
     * @notice Update the fee percentage
     * @param _feePercentage New fee percentage in basis points
     */
    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 1000, "Fee too high"); // Max 10%
        uint256 oldPercentage = feePercentage;
        feePercentage = _feePercentage;
        emit FeePercentageUpdated(oldPercentage, _feePercentage);
    }

    /**
     * @notice Update the auto-transfer threshold
     * @param _threshold New threshold amount
     */
    function setAutoTransferThreshold(uint256 _threshold) external onlyOwner {
        uint256 oldThreshold = autoTransferThreshold;
        autoTransferThreshold = _threshold;
        emit AutoTransferThresholdUpdated(oldThreshold, _threshold);
    }

    /**
     * @dev Authorize upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Receive ETH from pool manager
     */
    receive() external payable {}
}