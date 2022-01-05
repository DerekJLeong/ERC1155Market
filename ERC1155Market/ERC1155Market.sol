// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // Todo only use contracts-upgradeable?
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract HotSwapMarket is
    ReentrancyGuard,
    Initializable,
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable
{
    // structs and variables
    // declare and init counters
    using Counters for Counters.Counter;
    Counters.Counter private _collectionIds;
    Counters.Counter private _itemIds;
    Counters.Counter private _tokenIds;
    Counters.Counter private _itemsForSale;
    Counters.Counter private _itemsSold;
    // declare contract address, later set in the constructer
    address payable public contractAddress;
    // market fee structure
    uint256 public listingPrice = 0.0025 ether;
    uint256 public mintingPrice = 0.0001 ether;
    // ipfs uris for app
    string public ipfsUri = "https://ipfs.infura.io/ipfs/{id}.json";
    string public ipfsUriBase = "https://ipfs.infura.io/ipfs/";
    // struct for items and collections placed on the market
    struct MarketItem {
        address payable seller;
        address payable owner;
        bool forSale;
        bool sold;
        uint256 itemId;
        uint256 tokenId;
        uint256 price;
        uint256 associatedCollectionId;
    }
    struct Collection {
        address payable owner;
        uint256 collectionId;
        uint256 tokenId;
        uint256 collectionItemsSold;
        uint256 itemsInCollection;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {
        initialize();
    }

    function initialize() public initializer {
        __ERC1155_init(ipfsUri);
        __Ownable_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();

        contractAddress = payable(msg.sender);

        // Increment counters we dont want to start at 0 in constuctor
        _collectionIds.increment();
        _itemIds.increment();
        _tokenIds.increment();
    }

    // mappings
    mapping(uint256 => MarketItem) private idToItem;
    mapping(uint256 => Collection) private idToCollection;
    mapping(uint256 => string) private _uris;
    mapping(uint256 => mapping(uint256 => uint256))
        private IdToCollectionToItems;

    // events
    event MarketItemCreated(
        address seller,
        address owner,
        bool forSale,
        bool sold,
        uint256 indexed itemId,
        uint256 indexed tokenId,
        uint256 price,
        uint256 associatedCollectionId
    );
    event CollectionCreated(
        address owner,
        uint256 indexed collectionId,
        uint256 indexed tokenId,
        uint256 collectionItemsSold,
        uint256 itemsInCollection
    );

    //
    //  COLLECTION FUNCTIONS
    //

    // Mints collection token and adds collection to market
    function createCollection(uint256 tokenId) public returns (uint256) {
        _collectionIds.increment();
        uint256 collectionId = _itemIds.current();

        idToCollection[collectionId] = Collection(
            payable(msg.sender),
            collectionId,
            tokenId,
            0,
            0
        );

        safeTransferFrom(msg.sender, address(this), tokenId, 1, "");

        emit CollectionCreated(msg.sender, collectionId, tokenId, 0, 0);
        return collectionId;
    }

    // Removes an itemId to collectionsIds associated with a Collection
    function addItemToCollection(uint256 collectionId, uint256 itemId)
        public
        nonReentrant
    {
        require(
            idToCollection[collectionId].owner == msg.sender,
            "Must be collection owner"
        );
        require(
            idToItem[itemId].associatedCollectionId == 0,
            "Item already in a collection"
        );

        idToItem[itemId].associatedCollectionId = collectionId;
        IdToCollectionToItems[collectionId][itemId] = itemId;
        idToCollection[collectionId].itemsInCollection++;
    }

    // Adds an itemId to collectionsIds associated with a Collection
    function removeItemFromCollection(uint256 collectionId, uint256 itemId)
        public
        nonReentrant
    {
        require(
            IdToCollectionToItems[collectionId][itemId] >= 0, //TODO this may not be good enough
            "Item doesnt exist in collection"
        );
        require(
            idToCollection[collectionId].owner == msg.sender,
            "Must be collection owner"
        );
        require(
            idToItem[itemId].associatedCollectionId > 0,
            "Item not in a collection"
        );

        idToItem[itemId].associatedCollectionId = 0;
        delete IdToCollectionToItems[collectionId][itemId];
        idToCollection[collectionId].itemsInCollection--;
    }

    // Gets collection items at passed collectionId and itemid
    function getCollectionItem(uint256 collectionId, uint256 itemId)
        public
        view
        returns (uint256)
    {
        require(
            IdToCollectionToItems[collectionId][itemId] >= 0,
            "Collection item doesnt exist"
        );

        return IdToCollectionToItems[collectionId][itemId];
    }

    // Gets collection at passed collectionId
    function getCollection(uint256 collectionId)
        public
        view
        returns (Collection memory)
    {
        require(
            idToCollection[collectionId].collectionId >= 0,
            "Collection doesnt exist"
        );

        return idToCollection[collectionId];
    }

    // Gets collection at passed collectionId
    function getAmountOfCollectionItems(uint256 collectionId)
        public
        view
        returns (uint256)
    {
        require(
            idToCollection[collectionId].collectionId >= 0,
            "Collection doesnt exist"
        );

        return idToCollection[collectionId].itemsInCollection;
    }

    //
    //  ITEM FUNCTIONS
    //

    // Create market item with minted token
    function createItem(
        uint256 tokenId,
        uint256 price,
        uint256 collectionId
    ) public payable nonReentrant returns (uint256) {
        _itemIds.increment();
        uint256 itemId = _itemIds.current();
        uint256 itemPrice;
        uint256 associatedCollectionId;
        if (price > 0) {
            itemPrice = price;
        }
        if (price > 0) {
            associatedCollectionId = collectionId;
        }

        idToItem[itemId] = MarketItem(
            payable(msg.sender),
            payable(address(0)),
            false,
            false,
            itemId,
            tokenId,
            price,
            associatedCollectionId
        );

        safeTransferFrom(msg.sender, address(this), tokenId, 1, "");

        emit MarketItemCreated(
            msg.sender,
            address(0),
            false,
            false,
            itemId,
            tokenId,
            price,
            associatedCollectionId
        );
        return itemId;
    }

    // Gets item at passed itemId
    function getItem(uint256 id) public view returns (MarketItem memory) {
        require(idToItem[id].itemId > 0, "Item doesnt exist");

        return idToItem[id];
    }

    // Lists Market Item for Sale
    function listItemForSale(uint256 itemId, uint256 price)
        public
        payable
        nonReentrant
    {
        // bool forSaleStatus = idToItem[itemId].forSale;
        require(msg.sender == idToItem[itemId].seller, "Must be item seller");
        require(idToItem[itemId].forSale != true, "Item already for sale");
        require(price > 0, "Price must be at least 1wei");
        require(msg.value == listingPrice, "Fee must equal listing price");

        idToItem[itemId].forSale = true;
        idToItem[itemId].price = price;
        _itemsForSale.increment();
    }

    // Removes Market Item from Sale Listings
    function removeItemSaleListing(uint256 itemId) public payable nonReentrant {
        // bool forSaleStatus = idToItem[itemId].forSale;
        require(msg.sender == idToItem[itemId].seller, "Must be item seller");
        require(idToItem[itemId].forSale != false, "Item already NOT for sale");
        require(msg.value == listingPrice, "Fee must equal listing price");

        idToItem[itemId].forSale = false;
        _itemsForSale.decrement();
    }

    // Execute sale of listed market item
    // transfer token ownership and payment
    function executeSale(uint256 itemId) public payable nonReentrant {
        uint256 price = idToItem[itemId].price;
        uint256 tokenId = idToItem[itemId].tokenId;
        require(msg.value == price, "Asking price required");
        // (address(this), msg.sender, tokenId, 1, "");, "Asking price required");

        idToItem[itemId].owner = payable(msg.sender);
        idToItem[itemId].sold = true;
        idToItem[itemId].seller.transfer(msg.value);
        this.safeTransferFrom(address(this), msg.sender, tokenId, 1, "");
        _itemsSold.increment();
        payable(contractAddress).transfer(listingPrice);
    }

    //
    //  FETCHING FUNCTIONS FOR COLLECTIONS AND ITEMS
    //

    // Fetchs all items on the market
    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint256 itemCount = _tokenIds.current();
        uint256 unsoldItemCount = _tokenIds.current() - _itemsSold.current();
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        for (uint256 i = 0; i < itemCount; i++) {
            if (idToItem[i + 1].owner == address(0)) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }

        return items;
    }

    // Fetchs all collections
    function fetchMarketCollections()
        public
        view
        returns (Collection[] memory)
    {
        uint256 collectionCount = _collectionIds.current();
        Collection[] memory allCollections = new Collection[](collectionCount);
        for (uint256 i = 0; i < collectionCount; i++) {
            uint256 currentId = i + 1;
            Collection storage currentItem = idToCollection[currentId];
            allCollections[i] = currentItem;
        }
        return allCollections;
    }

    // Fetchs collections owned by sender
    function fetchMyCollections() public view returns (Collection[] memory) {
        uint256 totalItemCount = _tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToCollection[i].owner == msg.sender) {
                itemCount += 1;
            }
        }

        Collection[] memory myCollections = new Collection[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToCollection[i].owner == msg.sender) {
                Collection storage currentItem = idToCollection[i];
                myCollections[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return myCollections;
    }

    // Fetchs market items owned by sender
    function fetchMyItems() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (
                idToItem[i + 1].seller == msg.sender ||
                idToItem[i + 1].owner == msg.sender
            ) {
                itemCount += 1;
            }
        }

        MarketItem[] memory myItems = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (
                idToItem[i + 1].seller == msg.sender ||
                idToItem[i + 1].owner == msg.sender
            ) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToItem[currentId];
                myItems[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return myItems;
    }

    //
    //  CONTRACT UTILS
    //

    // Returns uri of token id, for fetching metaData
    function contractOwner() public view returns (address) {
        return contractAddress;
    }

    // Returns uri of token id, for fetching metaData
    function uri(uint256 tokenId) public view override returns (string memory) {
        return (
            string(
                abi.encodePacked(
                    ipfsUriBase,
                    Strings.toString(tokenId),
                    ".json"
                )
            )
        );
    }

    // Set env ipfsUri varaible and sets uri
    // should be syncd with ipfsUriBase
    function setURI(string memory newUri) public {
        ipfsUri = newUri;
        _setURI(newUri);
    }

    // Set env ipfsUriBase varaible and sets uri
    // should be syncd with ipfsUri
    function setURIBase(string memory newUriBase) public {
        ipfsUriBase = newUriBase;
    }

    // Sets uri associated with a token
    function setTokenURI(uint256 tokenId, string memory tokenUri) public {
        require(bytes(_uris[tokenId]).length == 0, "URI can only be set once");

        _uris[tokenId] = tokenUri;
    }

    // Used to get market listingPrice
    function getListingPrice() public view returns (uint256) {
        return listingPrice;
    }

    // Used to get market mintingPrice
    function getMintingPrice() public view returns (uint256) {
        return mintingPrice;
    }

    // Mint new erc1155 token; non-fungible or semi-fungible
    function mint(
        uint256 amount,
        string memory tokenUri,
        bytes memory data
    ) public returns (uint256) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(msg.sender, newItemId, amount, data);
        setTokenURI(newItemId, tokenUri);
        return newItemId;
    }

    // Todo
    // function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
    //     public
    // {
    //     _tokenIds.increment();
    //     uint256 newItemId = _tokenIds.current();
    //     _setTokenURI(newItemId, newuri);
    //     _mintBatch(to, ids, amounts, data);
    // }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
