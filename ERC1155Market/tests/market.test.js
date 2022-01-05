const { expect } = require("chai");
const { ethers } = require("hardhat");

const BLANK_ADDRESS = "0x0000000000000000000000000000000000000000";
const contractFileName = "HotSwapMarket";
const NON_FUNGIBLE = 1;
let MarketContract;
let hardhatMarket;
let owner;
let addr1;
let addr2;
let addrs;
let listingPrice;
let mintingPrice;

// before() is run once before all the tests in a describe
// after()   is run once after all the tests in a describe
// beforeEach() is run before each test in a describe
// afterEach()   is run after each test in a describe

beforeEach(async () => {
   // Get the ContractFactory and Signers here.
   MarketContract = await ethers.getContractFactory(contractFileName);
   [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
   hardhatMarket = await MarketContract.deploy();
});
describe("Market Contract Deployment", () => {
   it("Should set the correct owner", async () => {
      const contractOwner = await hardhatMarket.contractOwner();
      expect(contractOwner).to.equal(owner.address);
   });
   // it("Contract Migrates Correctly", async () => {});
});
describe("Market Contract Transactions", () => {
   const tokenUri = "https://www.myimagelocation1.com";
   const metaDataUri = "https://www.myimagelocation1.com";

   it("Can get fee structure", async () => {
      listingPrice = await hardhatMarket.getListingPrice();
      mintingPrice = await hardhatMarket.getMintingPrice();
      expect(!!listingPrice).to.equal(true);
      expect(!!mintingPrice).to.equal(true);
   });

   describe("ERC1155 Token Creation", () => {
      it("Can mint non-fungible tokens", async () => {
         const supply = 1;
         let transaction = await hardhatMarket.mint(supply, metaDataUri, []);
         transaction = await transaction.wait();
         expect(transaction.events[0].args.value).to.equal(supply);
      });
      it("Can mint semi-fungible tokens", async () => {
         const supply = 1000;
         let transaction = await hardhatMarket.mint(supply, metaDataUri, []);
         transaction = await transaction.wait();
         expect(transaction.events[0].args.value).to.equal(supply);
      });
      it("Can set token URI only once", async () => {
         const supply = 1;
         let transaction = await hardhatMarket.mint(supply, metaDataUri, []);
         transaction = await transaction.wait();

         let success;
         try {
            await hardhatMarket.setTokenURI(2, metaDataUri);
            success = true;
         } catch {
            success = false;
         }
         expect(success).to.equal(false);
      });
   });

   describe("Collections", () => {
      let transaction;
      beforeEach(async () => {
         await hardhatMarket.mint(NON_FUNGIBLE, tokenUri, []);
         transaction = await hardhatMarket.createCollection(2);
         transaction = await transaction.wait();
      });
      it("Can be created", async () => {
         expect(transaction.events[1].args.length).to.equal(5);
      });
      it("Can be retrieved by id", async () => {
         const id = 1;
         const createdCollection = await hardhatMarket.getCollection(id);
         expect(createdCollection.collectionId).to.equal(id);
      });
      it("Can add items to collections", async () => {
         const id = 1;
         const itemId = 424242;
         await hardhatMarket.addItemToCollection(id, itemId);
         const collectionWithItem = await hardhatMarket.getCollection(id);
         expect(collectionWithItem.itemsInCollection).to.equal(1);
      });
      it("Can retrieve all collections", async () => {
         const collections = await hardhatMarket.fetchMarketCollections();
         expect(collections.length).to.equal(2);
      });
      it("Can retrieve all collections mapped to sender address", async () => {
         const collections = await hardhatMarket.fetchMyCollections();
         expect(collections.length).to.equal(1);
      });
   });

   describe("Items", async () => {
      let transaction;
      let _itemId;
      const tokenPrice = 42;
      beforeEach(async () => {
         await hardhatMarket.mint(NON_FUNGIBLE, tokenUri, []);
         transaction = await hardhatMarket.createItem(2, tokenPrice, 0);
         transaction = await transaction.wait();
      });
      it("Can be created", async () => {
         const [
            sellerAddress,
            ownerAddress,
            forSale,
            sold,
            itemId,
            tokenId,
            price,
            associatedCollectionId,
         ] = transaction.events[1].args;

         expect(sold).to.equal(false);
         expect(forSale).to.equal(false);
         expect(sellerAddress).to.equal(owner.address);
         expect(ownerAddress).to.equal(BLANK_ADDRESS);
         expect(itemId).to.equal(2);
         expect(Number(tokenId)).to.equal(2);
         expect(price).to.equal(tokenPrice);
         expect(associatedCollectionId).to.equal(0);
         _itemId = itemId;
      });
      it("Can be retrieved by id", async () => {
         const fetchedItem = await hardhatMarket.getItem(_itemId);
         // Expect created collection id to be the first index in our map
         expect(fetchedItem.itemId).to.equal(_itemId);
      });
      it("Can be added or removed from sale", async () => {
         // List for sale, then fetch the item and check for sale status
         await hardhatMarket.listItemForSale(_itemId, tokenPrice, {
            value: listingPrice,
         });
         let fetchedItem = await hardhatMarket.getItem(_itemId);
         expect(fetchedItem.forSale).to.equal(true);

         // remove sale listing, then fetch the item and check for sale status
         await hardhatMarket.removeItemSaleListing(_itemId, {
            value: listingPrice,
         });
         fetchedItem = await hardhatMarket.getItem(_itemId);
         expect(fetchedItem.forSale).to.equal(false);
      });
      it("Item sales execute correctly", async () => {
         await hardhatMarket.listItemForSale(_itemId, tokenPrice, {
            value: listingPrice,
         });
         let fetchedItem = await hardhatMarket.getItem(_itemId);
         expect(fetchedItem.forSale).to.equal(true);
         expect(fetchedItem.sold).to.equal(false);
         await hardhatMarket.connect(addr1).executeSale(_itemId, {
            value: tokenPrice,
         });
         fetchedItem = await hardhatMarket.getItem(_itemId);
         expect(fetchedItem.forSale).to.equal(true);
         expect(fetchedItem.sold).to.equal(true);
      });
      it("Can retrieve all Items on market", async () => {
         const items = await hardhatMarket.fetchMarketItems();
         expect(items.length).to.equal(2);
      });
      it("Can retrieve all collections mapped to sender address", async () => {
         const collections = await hardhatMarket.fetchMyItems();
         expect(collections.length).to.equal(1);
      });
   });
});
