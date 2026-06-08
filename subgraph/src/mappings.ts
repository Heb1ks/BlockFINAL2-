import {
    BigInt,
    Bytes,
    log,
} from "@graphprotocol/graph-ts"

// GameToken events
import { Transfer as TransferEvent } from "../generated/GameToken/GameToken"

// GameAMM events
import {
    Swap as SwapEvent,
    LiquidityAdded as LiquidityAddedEvent,
    LiquidityRemoved as LiquidityRemovedEvent,
} from "../generated/GameAMM/GameAMM"

// NFTRentalVault events
import {
    ItemListed as ItemListedEvent,
    ItemRented as ItemRentedEvent,
    RentalEnded as RentalEndedEvent,
    ItemDelisted as ItemDelistedEvent,
} from "../generated/NFTRentalVault/NFTRentalVault"

// GameDAO events
import {
    ProposalCreated as ProposalCreatedEvent,
    VoteCast as VoteCastEvent,
    ProposalQueued as ProposalQueuedEvent,
    ProposalExecuted as ProposalExecutedEvent,
    ProposalCanceled as ProposalCanceledEvent,
} from "../generated/GameDAO/GameDAO"

// LootDrop events
import {
    LootRequested as LootRequestedEvent,
    LootFulfilled as LootFulfilledEvent,
} from "../generated/LootDrop/LootDrop"

// Entities
import {
    TokenTransfer,
    Swap,
    LiquidityEvent,
    AMMPool,
    Listing,
    Rental,
    Proposal,
    Vote,
    LootRequest,
} from "../generated/schema"

//  Constants 

const AMM_POOL_ID = Bytes.fromHexString("0x00")

//  GameToken 

export function handleTransfer(event: TransferEvent): void {
    let entity = new TokenTransfer(
        event.transaction.hash.concatI32(event.logIndex.toI32())
    )
    entity.from = event.params.from
    entity.to   = event.params.to
    entity.value = event.params.value
    entity.blockNumber = event.block.number
    entity.timestamp = event.block.timestamp
    entity.transactionHash = event.transaction.hash
    entity.save()
}

//  GameAMM 

function loadOrCreatePool(): AMMPool {
    let pool = AMMPool.load(AMM_POOL_ID)
    if (pool == null) {
        pool = new AMMPool(AMM_POOL_ID)
        pool.totalVolumeA = BigInt.fromI32(0)
        pool.totalVolumeB = BigInt.fromI32(0)
        pool.swapCount    = BigInt.fromI32(0)
        pool.liquidityProviderCount = BigInt.fromI32(0)
    }
    return pool as AMMPool
}

export function handleSwap(event: SwapEvent): void {
    let swap = new Swap(
        event.transaction.hash.concatI32(event.logIndex.toI32())
    )
    swap.user      = event.params.user
    swap.amountIn  = event.params.amountIn
    swap.amountOut = event.params.amountOut
    swap.aToB      = event.params.aToB
    swap.blockNumber = event.block.number
    swap.timestamp = event.block.timestamp
    swap.transactionHash = event.transaction.hash
    swap.save()

    // Update pool stats
    let pool = loadOrCreatePool()
    pool.swapCount = pool.swapCount.plus(BigInt.fromI32(1))
    if (event.params.aToB) {
        pool.totalVolumeA = pool.totalVolumeA.plus(event.params.amountIn)
        pool.totalVolumeB = pool.totalVolumeB.plus(event.params.amountOut)
    } else {
        pool.totalVolumeB = pool.totalVolumeB.plus(event.params.amountIn)
        pool.totalVolumeA = pool.totalVolumeA.plus(event.params.amountOut)
    }
    pool.save()
}

export function handleLiquidityAdded(event: LiquidityAddedEvent): void {
    let liq = new LiquidityEvent(
        event.transaction.hash.concatI32(event.logIndex.toI32())
    )
    liq.user    = event.params.user
    liq.amountA = event.params.amountA
    liq.amountB = event.params.amountB
    liq.shares  = event.params.shares
    liq.isAdd   = true
    liq.blockNumber = event.block.number
    liq.timestamp = event.block.timestamp
    liq.transactionHash = event.transaction.hash
    liq.save()

    let pool = loadOrCreatePool()
    pool.liquidityProviderCount = pool.liquidityProviderCount.plus(BigInt.fromI32(1))
    pool.save()
}

export function handleLiquidityRemoved(event: LiquidityRemovedEvent): void {
    let liq = new LiquidityEvent(
        event.transaction.hash.concatI32(event.logIndex.toI32())
    )
    liq.user    = event.params.user
    liq.amountA = event.params.amountA
    liq.amountB = event.params.amountB
    liq.shares  = event.params.shares
    liq.isAdd   = false
    liq.blockNumber = event.block.number
    liq.timestamp = event.block.timestamp
    liq.transactionHash = event.transaction.hash
    liq.save()
}

//  NFTRentalVault 

export function handleItemListed(event: ItemListedEvent): void {
    let listing = new Listing(event.params.listingId.toString())
    listing.owner       = event.params.owner
    listing.itemId      = event.params.itemId
    listing.amount      = event.params.amount
    listing.pricePerDay = event.params.pricePerDay
    listing.active      = true
    listing.createdAt   = event.block.timestamp
    listing.save()
}

export function handleItemRented(event: ItemRentedEvent): void {
    let rental = new Rental(event.params.rentalId.toString())
    rental.listing   = event.params.listingId.toString()
    rental.renter    = event.params.renter
    rental.startTime = event.block.timestamp
    rental.endTime   = event.params.endTime
    rental.active    = true
    rental.transactionHash = event.transaction.hash
    rental.save()

    // Mark listing as inactive while rented
    let listing = Listing.load(event.params.listingId.toString())
    if (listing != null) {
        listing.active = false
        listing.save()
    }
}

export function handleRentalEnded(event: RentalEndedEvent): void {
    let rental = Rental.load(event.params.rentalId.toString())
    if (rental != null) {
        rental.active = false
        rental.save()
    }

    // Re-activate listing
    let listing = Listing.load(event.params.listingId.toString())
    if (listing != null) {
        listing.active = true
        listing.save()
    }
}

export function handleItemDelisted(event: ItemDelistedEvent): void {
    let listing = Listing.load(event.params.listingId.toString())
    if (listing != null) {
        listing.active = false
        listing.save()
    }
}

//  GameDAO 

export function handleProposalCreated(event: ProposalCreatedEvent): void {
    let proposal = new Proposal(event.params.proposalId.toString())
    proposal.proposalId    = event.params.proposalId
    proposal.proposer      = event.params.proposer
    proposal.description   = event.params.description
    proposal.startBlock    = event.params.voteStart
    proposal.endBlock      = event.params.voteEnd
    proposal.forVotes      = BigInt.fromI32(0)
    proposal.againstVotes  = BigInt.fromI32(0)
    proposal.abstainVotes  = BigInt.fromI32(0)
    proposal.state         = "Active"
    proposal.createdAt     = event.block.timestamp
    proposal.transactionHash = event.transaction.hash
    proposal.save()
}

export function handleVoteCast(event: VoteCastEvent): void {
    let voteId = event.transaction.hash.concatI32(event.logIndex.toI32())
    let vote = new Vote(voteId)
    vote.proposal  = event.params.proposalId.toString()
    vote.voter     = event.params.voter
    vote.support   = event.params.support
    vote.weight    = event.params.weight
    vote.timestamp = event.block.timestamp
    vote.transactionHash = event.transaction.hash
    vote.save()

    // Update proposal vote counts
    let proposal = Proposal.load(event.params.proposalId.toString())
    if (proposal != null) {
        if (event.params.support == 0) {
            proposal.againstVotes = proposal.againstVotes.plus(event.params.weight)
        } else if (event.params.support == 1) {
            proposal.forVotes = proposal.forVotes.plus(event.params.weight)
        } else {
            proposal.abstainVotes = proposal.abstainVotes.plus(event.params.weight)
        }
        proposal.save()
    }
}

export function handleProposalQueued(event: ProposalQueuedEvent): void {
    let proposal = Proposal.load(event.params.proposalId.toString())
    if (proposal != null) {
        proposal.state = "Queued"
        proposal.save()
    }
}

export function handleProposalExecuted(event: ProposalExecutedEvent): void {
    let proposal = Proposal.load(event.params.proposalId.toString())
    if (proposal != null) {
        proposal.state = "Executed"
        proposal.save()
    }
}

export function handleProposalCanceled(event: ProposalCanceledEvent): void {
    let proposal = Proposal.load(event.params.proposalId.toString())
    if (proposal != null) {
        proposal.state = "Canceled"
        proposal.save()
    }
}

//  LootDrop 

export function handleLootRequested(event: LootRequestedEvent): void {
    let request = new LootRequest(event.params.requestId.toString())
    request.requestId  = event.params.requestId
    request.player     = event.params.player
    request.fulfilled  = false
    request.timestamp  = event.block.timestamp
    request.transactionHash = event.transaction.hash
    request.save()
}

export function handleLootFulfilled(event: LootFulfilledEvent): void {
    let request = LootRequest.load(event.params.requestId.toString())
    if (request != null) {
        request.fulfilled = true
        if (event.params.dropped) {
            request.itemId = event.params.itemId
        }
        request.save()
    }
}
