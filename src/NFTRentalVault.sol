// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title NFTRentalVault - rent out ERC-1155 game items for GAME tokens
contract NFTRentalVault is ERC1155Holder, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC1155 public immutable GAME_ITEMS;
    IERC20 public immutable GAME_TOKEN;

    uint256 public constant MAX_RENTAL_DURATION = 7 days;
    uint256 public platformFee = 50; // 5%
    uint256 public constant FEE_DENOMINATOR = 1000;

    struct Listing {
        address owner;
        uint256 itemId;
        uint256 amount;
        uint256 pricePerDay;
        bool active;
    }

    struct Rental {
        address renter;
        uint256 listingId;
        uint256 startTime;
        uint256 endTime;
        bool active;
    }

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Rental) public rentals;
    uint256 public listingCount;
    uint256 public rentalCount;

    event Listed(uint256 indexed listingId, address indexed owner, uint256 itemId, uint256 pricePerDay);
    event Rented(uint256 indexed rentalId, address indexed renter, uint256 listingId, uint256 duration);
    event RentalEnded(uint256 indexed rentalId);
    event Delisted(uint256 indexed listingId);

    constructor(address _gameItems, address _gameToken, address _owner) Ownable(_owner) {
        GAME_ITEMS = IERC1155(_gameItems);
        GAME_TOKEN = IERC20(_gameToken);
    }

    function listItem(uint256 itemId, uint256 amount, uint256 pricePerDay)
        external
        nonReentrant
        returns (uint256 listingId)
    {
        require(amount > 0, "Zero amount");
        require(pricePerDay > 0, "Zero price");

        GAME_ITEMS.safeTransferFrom(msg.sender, address(this), itemId, amount, "");

        listingId = listingCount++;
        listings[listingId] =
            Listing({owner: msg.sender, itemId: itemId, amount: amount, pricePerDay: pricePerDay, active: true});

        emit Listed(listingId, msg.sender, itemId, pricePerDay);
    }

    function rentItem(uint256 listingId, uint256 durationDays) external nonReentrant returns (uint256 rentalId) {
        require(durationDays > 0 && durationDays * 1 days <= MAX_RENTAL_DURATION, "Invalid duration");
        Listing storage listing = listings[listingId];
        require(listing.active, "Not active");
        require(listing.owner != msg.sender, "Cannot rent own item");

        uint256 totalCost = listing.pricePerDay * durationDays;
        uint256 fee = (totalCost * platformFee) / FEE_DENOMINATOR;
        uint256 ownerAmount = totalCost - fee;

        GAME_TOKEN.safeTransferFrom(msg.sender, listing.owner, ownerAmount);
        GAME_TOKEN.safeTransferFrom(msg.sender, address(this), fee);

        listing.active = false;

        rentalId = rentalCount++;
        rentals[rentalId] = Rental({
            renter: msg.sender,
            listingId: listingId,
            startTime: block.timestamp,
            endTime: block.timestamp + durationDays * 1 days,
            active: true
        });

        emit Rented(rentalId, msg.sender, listingId, durationDays);
    }

    function endRental(uint256 rentalId) external nonReentrant {
        Rental storage rental = rentals[rentalId];
        require(rental.active, "Not active");
        require(block.timestamp >= rental.endTime, "Rental not expired");

        Listing storage listing = listings[rental.listingId];
        rental.active = false;
        listing.active = true;

        emit RentalEnded(rentalId);
    }

    function delistItem(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.owner == msg.sender, "Not owner");
        require(listing.active, "Not active");

        listing.active = false;
        GAME_ITEMS.safeTransferFrom(address(this), msg.sender, listing.itemId, listing.amount, "");

        emit Delisted(listingId);
    }

    function setPlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= 100, "Max 10%");
        platformFee = newFee;
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = GAME_TOKEN.balanceOf(address(this));
        GAME_TOKEN.safeTransfer(owner(), balance);
    }
}
