// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IGnomeStickers {
    function balanceOf(address owner) external view returns (uint256);
    function hookMint() external;
    function getCurrentMintPrice() external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/**
 * @title GnomelandHook - Auto-Minting Hook with NFT Holder Benefits
 * @notice Collects fees and auto-mints NFTs
 * @dev NFT holders trade with 0% fees! 🍄✨
 */
contract GnomelandHook is 
    BaseHook, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable 
{
    using PoolIdLibrary for PoolKey;

    address public nftContract;
    uint256 public feePercentage; // Fee for non-holders
    uint256 public accumulatedFees;
    
    // Stats
    uint256 public totalFeesCollected;
    uint256 public totalFeesSaved; // By NFT holders
    uint256 public freeTradesCount; // Number of fee-free swaps
    
    event FeesCollected(address indexed pool, address indexed swapper, uint256 amount, bool isNFTHolder);
    event AutoMinted(uint256 tokenId, uint256 cost);
    event FeesForwarded(address indexed nftContract, uint256 amount);
    event FreeTradeUsed(address indexed holder, uint256 feesSaved);
    event NFTContractUpdated(address indexed oldContract, address indexed newContract);
    event FeePercentageUpdated(uint256 oldPercentage, uint256 newPercentage);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        _disableInitializers();
    }

    function initialize(
        address _nftContract,
        uint256 _feePercentage
    ) external initializer {
        require(_nftContract != address(0), "Invalid NFT contract");
        require(_feePercentage <= 1000, "Fee too high"); // Max 10%
        
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        nftContract = _nftContract;
        feePercentage = _feePercentage;
    }

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
     * @dev NFT holders pay 0% fees! 🍄✨
     */
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        uint256 swapAmount = params.amountSpecified > 0 
            ? uint256(params.amountSpecified) 
            : uint256(-params.amountSpecified);
        
        // Check if swapper owns any NFTs
        bool isNFTHolder = _isNFTHolder(sender);
        
        uint256 feeAmount = 0;
        
        if (isNFTHolder) {
            // 🎉 FREE TRADE for NFT holders!
            feeAmount = 0;
            
            // Track savings
            uint256 wouldHavePaid = (swapAmount * feePercentage) / 10000;
            totalFeesSaved += wouldHavePaid;
            freeTradesCount++;
            
            emit FreeTradeUsed(sender, wouldHavePaid);
        } else {
            // Regular fee for non-holders
            feeAmount = (swapAmount * feePercentage) / 10000;
            
            if (feeAmount > 0) {
                accumulatedFees += feeAmount;
                totalFeesCollected += feeAmount;
            }
        }
        
        emit FeesCollected(
            address(uint160(uint256(PoolId.unwrap(key.toId())))), 
            sender,
            feeAmount,
            isNFTHolder
        );
        
        // Try to auto-mint if we have enough fees
        if (accumulatedFees > 0) {
            _tryAutoMint();
        }
        
        return (BaseHook.afterSwap.selector, 0);
    }

    /**
     * @notice Check if address owns at least one NFT
     * @param holder Address to check
     * @return true if holder owns >= 1 NFT
     */
    function _isNFTHolder(address holder) internal view returns (bool) {
        try IGnomeStickers(nftContract).balanceOf(holder) returns (uint256 balance) {
            return balance > 0;
        } catch {
            return false; // If call fails, assume not a holder
        }
    }

    /**
     * @notice Check if an address is an NFT holder (public view)
     */
    function isNFTHolder(address holder) external view returns (bool) {
        return _isNFTHolder(holder);
    }

    /**
     * @notice Calculate what fee WOULD be charged (for display purposes)
     */
    function calculateFee(address swapper, uint256 swapAmount) external view returns (uint256) {
        if (_isNFTHolder(swapper)) {
            return 0; // NFT holders pay nothing! 🍄
        }
        return (swapAmount * feePercentage) / 10000;
    }

    /**
     * @notice Try to mint a new NFT if we have enough fees
     */
    function _tryAutoMint() internal {
        try IGnomeStickers(nftContract).getCurrentMintPrice() returns (uint256 mintPrice) {
            // Check if we have enough + buffer for gas
            if (accumulatedFees >= mintPrice + 0.01 ether) {
                // Forward fees to NFT contract
                uint256 toSend = accumulatedFees;
                accumulatedFees = 0;
                
                (bool success, ) = nftContract.call{value: toSend}("");
                require(success, "Fee transfer failed");
                
                emit FeesForwarded(nftContract, toSend);
                
                // Trigger mint
                try IGnomeStickers(nftContract).hookMint() {
                    uint256 supply = IGnomeStickers(nftContract).totalSupply();
                    emit AutoMinted(supply - 1, mintPrice);
                } catch {
                    // Mint failed, fees are still in NFT contract for next time
                }
            }
        } catch {
            // Could not get mint price, skip for now
        }
    }

    /**
     * @notice Manually trigger mint (admin)
     */
    function manualMint() external onlyOwner nonReentrant {
        require(accumulatedFees > 0, "No fees to forward");
        
        uint256 toSend = accumulatedFees;
        accumulatedFees = 0;
        
        (bool success, ) = nftContract.call{value: toSend}("");
        require(success, "Fee transfer failed");
        
        emit FeesForwarded(nftContract, toSend);
        
        IGnomeStickers(nftContract).hookMint();
    }

    /**
     * @notice Update NFT contract address
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        require(_nftContract != address(0), "Invalid address");
        address oldContract = nftContract;
        nftContract = _nftContract;
        emit NFTContractUpdated(oldContract, _nftContract);
    }

    /**
     * @notice Update fee percentage for non-holders
     */
    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 1000, "Fee too high"); // Max 10%
        uint256 oldPercentage = feePercentage;
        feePercentage = _feePercentage;
        emit FeePercentageUpdated(oldPercentage, _feePercentage);
    }

    /**
     * @notice Get comprehensive stats
     */
    function getStats() external view returns (
        uint256 _accumulatedFees,
        uint256 _totalFeesCollected,
        uint256 _totalFeesSaved,
        uint256 _freeTradesCount,
        uint256 _feePercentage
    ) {
        return (
            accumulatedFees,
            totalFeesCollected,
            totalFeesSaved,
            freeTradesCount,
            feePercentage
        );
    }

    /**
     * @dev Authorize upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Receive ETH
     */
    receive() external payable {}
}