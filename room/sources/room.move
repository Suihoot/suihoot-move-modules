/// Module: room
/// On-chain Kahoot game system with encrypted questions using Seal and Walrus storage
module room::room;

use std::bcs;
use std::string::{Self, String};
use sui::bcs::{BCS, new};
use sui::clock::{Self, Clock};
use sui::event;
use sui::hash;
use sui::table::{Self, Table};

// ======== Constants ========
const MAX_PARTICIPANTS: u64 = 100;
const MAX_QUESTIONS: u64 = 50;
const ANSWER_TIME_LIMIT: u64 = 30000; // 30 seconds in milliseconds

// ======== Error codes ========
const ENotCreator: u64 = 1;
const ERoomNotOpen: u64 = 2;
const ERoomFull: u64 = 3;
const EAlreadyJoined: u64 = 4;
const ENotParticipant: u64 = 5;
const ERoomNotStarted: u64 = 6;
const EQuestionNotActive: u64 = 7;
const EAlreadyAnswered: u64 = 8;
const ETimeExpired: u64 = 9;
const EInvalidQuestionIndex: u64 = 10;
const ENoAccess: u64 = 11;

// ======== Structs ========

/// Represents an encrypted question stored on Walrus
public struct EncryptedQuestion has copy, drop, store {
    walrus_hash: String, // Hash returned by Walrus for the encrypted question
}

/// Represents a decrypted question (revealed during gameplay)
/// Hot potato
public struct Question has copy, drop, store {
    text: String,
    options: vector<String>,
    correct_answer_hash: vector<u8>,
    revealed_at: u64,
}

/// Participant information
public struct Participant has store {
    player: address,
    joined_at: u64,
    total_score: u64,
    answers: Table<u64, ParticipantAnswer>, // question_index -> answer
}

/// Answer submitted by participant
public struct ParticipantAnswer has copy, drop, store {
    answer_hash: vector<u8>,
    submitted_at: u64,
    is_correct: bool,
    points_earned: u64,
}

/// Game room state
public struct GameRoom has key, store {
    id: UID,
    creator: address,
    title: String,
    description: String,
    encrypted_questions: vector<EncryptedQuestion>,
    revealed_questions: Table<u64, Question>, // question_index -> revealed question
    participants: Table<address, Participant>,
    participant_addresses: vector<address>,
    status: u8, // 0: Open, 1: Started, 2: Completed
    current_question_index: u64,
    question_start_time: u64,
    max_participants: u64,
    created_at: u64,
    prize_pool: u64, // Optional prize pool
    leaderboard: vector<LeaderboardEntry>,
}

/// Leaderboard entry
public struct LeaderboardEntry has copy, drop, store {
    player: address,
    total_score: u64,
    rank: u64,
}

/// Room creation capability
public struct CreatorCap has key, store {
    id: UID,
    room_id: address,
}

// ======== Events ========

public struct RoomCreated has copy, drop {
    room_id: address,
    creator: address,
    title: String,
    total_questions: u64,
}

public struct ParticipantJoined has copy, drop {
    room_id: address,
    participant: address,
    total_participants: u64,
}

public struct GameStarted has copy, drop {
    room_id: address,
    started_by: address,
    total_participants: u64,
}

public struct QuestionRevealed has copy, drop {
    room_id: address,
    question_index: u64,
    question_text: String,
    options: vector<String>,
}

public struct AnswerSubmitted has copy, drop {
    room_id: address,
    participant: address,
    question_index: u64,
    is_correct: bool,
    points_earned: u64,
}

public struct QuestionCompleted has copy, drop {
    room_id: address,
    question_index: u64,
    total_answers: u64,
}

public struct GameCompleted has copy, drop {
    room_id: address,
    winner: address,
    total_participants: u64,
}

// ======== Public Functions ========

/// Create a new game room with encrypted questions
public fun create_room(
    title: String,
    description: String,
    encrypted_questions: vector<EncryptedQuestion>,
    max_participants: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (GameRoom, CreatorCap) {
    assert!(vector::length(&encrypted_questions) > 0, EInvalidQuestionIndex);
    assert!(vector::length(&encrypted_questions) <= MAX_QUESTIONS, EInvalidQuestionIndex);
    assert!(max_participants > 0 && max_participants <= MAX_PARTICIPANTS, ERoomFull);

    let room_id = object::new(ctx);
    let room_address = object::uid_to_address(&room_id);

    let room = GameRoom {
        id: room_id,
        creator: ctx.sender(),
        title: title,
        description: description,
        encrypted_questions,
        revealed_questions: table::new(ctx),
        participants: table::new(ctx),
        participant_addresses: vector::empty(),
        status: 0, // Open
        current_question_index: 0,
        question_start_time: 0,
        max_participants,
        created_at: clock::timestamp_ms(clock),
        prize_pool: 0,
        leaderboard: vector::empty(),
    };

    let creator_cap = CreatorCap {
        id: object::new(ctx),
        room_id: room_address,
    };

    // Emit room created event
    event::emit(RoomCreated {
        room_id: room_address,
        creator: ctx.sender(),
        title: room.title,
        total_questions: vector::length(&room.encrypted_questions),
    });

    (room, creator_cap)
}

/// Join a game room as a participant
public fun join_room(room: &mut GameRoom, clock: &Clock, ctx: &mut TxContext) {
    let participant_addr = ctx.sender();
    assert!(room.status == 0, ERoomNotOpen);
    assert!(vector::length(&room.participant_addresses) < room.max_participants, ERoomFull);
    assert!(!table::contains(&room.participants, participant_addr), EAlreadyJoined);

    let participant = Participant {
        player: participant_addr,
        joined_at: clock::timestamp_ms(clock),
        total_score: 0,
        answers: table::new(ctx),
    };

    table::add(&mut room.participants, participant_addr, participant);
    vector::push_back(&mut room.participant_addresses, participant_addr);

    // Emit participant joined event
    event::emit(ParticipantJoined {
        room_id: object::uid_to_address(&room.id),
        participant: participant_addr,
        total_participants: vector::length(&room.participant_addresses),
    });
}

/// Start the game (only creator can start)
public fun start_game(
    room: &mut GameRoom,
    _creator_cap: &CreatorCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(room.creator == ctx.sender(), ENotCreator);
    assert!(room.status == 0, ERoomNotOpen);
    assert!(vector::length(&room.participant_addresses) > 0, ERoomNotOpen);

    room.status = 1; // Started

    // Reveal first question
    // reveal_question(room, 0, clock, ctx);

    // Emit game started event
    event::emit(GameStarted {
        room_id: object::uid_to_address(&room.id),
        started_by: ctx.sender(),
        total_participants: vector::length(&room.participant_addresses),
    });
}

/// Reveal a question by decrypting it on-chain (simplified decryption logic)
/* fun reveal_question(room: &mut GameRoom, question_index: u64, clock: &Clock, _ctx: &TxContext) {
    assert!(question_index < vector::length(&room.encrypted_questions), EInvalidQuestionIndex);

    let encrypted_q = vector::borrow(&room.encrypted_questions, question_index);

    // In a real implementation, this would involve actual Seal decryption
    // For now, we simulate decryption by extracting data from sealed_data
    let (question_text, options) = simulate_decrypt(&encrypted_q.sealed_data);

    let revealed_question = Question {
        text: question_text,
        options: options,
        correct_answer_hash: encrypted_q.answer_hash,
        revealed_at: clock::timestamp_ms(clock),
    };

    table::add(&mut room.revealed_questions, question_index, revealed_question);
    room.current_question_index = question_index;
    room.question_start_time = clock::timestamp_ms(clock);

    // Emit question revealed event
    let revealed_q = table::borrow(&room.revealed_questions, question_index);
    event::emit(QuestionRevealed {
        room_id: object::uid_to_address(&room.id),
        question_index,
        question_text: revealed_q.text,
        options: revealed_q.options,
    });
} */

/// Submit an answer for the current question
public fun submit_answer(room: &mut GameRoom, answer: String, clock: &Clock, ctx: &mut TxContext) {
    let participant_addr = ctx.sender();
    assert!(room.status == 1, ERoomNotStarted);
    assert!(table::contains(&room.participants, participant_addr), ENotParticipant);

    let current_time = clock::timestamp_ms(clock);
    assert!(current_time <= room.question_start_time + ANSWER_TIME_LIMIT, ETimeExpired);

    let participant = table::borrow_mut(&mut room.participants, participant_addr);
    assert!(!table::contains(&participant.answers, room.current_question_index), EAlreadyAnswered);

    // Hash the submitted answer
    let answer_hash = hash::keccak256(string::as_bytes(&answer));

    // Get the current question
    let current_question = table::borrow(&room.revealed_questions, room.current_question_index);

    // Check if answer is correct by comparing hashes
    let is_correct = answer_hash == current_question.correct_answer_hash;

    // @todo: implement point scoring based on answer speed and correctness
    let points_earned = if (is_correct) 1 else 0;

    // Record the answer
    let participant_answer = ParticipantAnswer {
        answer_hash,
        submitted_at: current_time,
        is_correct,
        points_earned,
    };

    table::add(&mut participant.answers, room.current_question_index, participant_answer);
    participant.total_score = participant.total_score + points_earned;

    // Emit answer submitted event
    event::emit(AnswerSubmitted {
        room_id: object::uid_to_address(&room.id),
        participant: participant_addr,
        question_index: room.current_question_index,
        is_correct,
        points_earned,
    });
}

/// Move to the next question (only creator can do this)
public fun next_question(
    room: &mut GameRoom,
    _creator_cap: &CreatorCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(room.creator == ctx.sender(), ENotCreator);
    assert!(room.status == 1, ERoomNotStarted);

    let next_index = room.current_question_index + 1;

    // Emit question completed event for current question
    let total_answers = count_answers_for_question(room, room.current_question_index);
    event::emit(QuestionCompleted {
        room_id: object::uid_to_address(&room.id),
        question_index: room.current_question_index,
        total_answers,
    });

    if (next_index >= vector::length(&room.encrypted_questions)) {
        // Game completed, calculate final leaderboard
        complete_game(room, ctx);
    } else {}
}

/// Complete the game and determine winner
fun complete_game(room: &mut GameRoom, _ctx: &TxContext) {
    room.status = 2; // Completed

    // Calculate leaderboard
    update_leaderboard(room);

    // Determine winner (highest score)
    let winner = if (vector::length(&room.leaderboard) > 0) {
        let top_entry = vector::borrow(&room.leaderboard, 0);
        top_entry.player
    } else {
        @0x0 // No winner if no participants
    };

    // Emit game completed event
    event::emit(GameCompleted {
        room_id: object::uid_to_address(&room.id),
        winner,
        total_participants: vector::length(&room.participant_addresses),
    });
}

/// Update the leaderboard based on current scores
fun update_leaderboard(room: &mut GameRoom) {
    room.leaderboard = vector::empty();

    let mut i = 0;
    while (i < vector::length(&room.participant_addresses)) {
        let addr = *vector::borrow(&room.participant_addresses, i);
        let participant = table::borrow(&room.participants, addr);

        let entry = LeaderboardEntry {
            player: addr,
            total_score: participant.total_score,
            rank: 0, // Will be calculated after sorting
        };

        vector::push_back(&mut room.leaderboard, entry);
        i = i + 1;
    };

    // Sort leaderboard by score (simplified - in practice would need proper sorting)
    // For now, just assign ranks based on order
    let mut j = 0;
    while (j < vector::length(&room.leaderboard)) {
        let entry = vector::borrow_mut(&mut room.leaderboard, j);
        entry.rank = j + 1;
        j = j + 1;
    };
}

/// Count answers for a specific question
fun count_answers_for_question(room: &GameRoom, question_index: u64): u64 {
    let mut count = 0;
    let mut i = 0;

    while (i < vector::length(&room.participant_addresses)) {
        let addr = *vector::borrow(&room.participant_addresses, i);
        let participant = table::borrow(&room.participants, addr);

        if (table::contains(&participant.answers, question_index)) {
            count = count + 1;
        };

        i = i + 1;
    };

    count
}

/// Simulate decryption (in real implementation, this would use Seal)
fun simulate_decrypt(_sealed_data: &vector<u8>): (String, vector<String>) {
    // This is a placeholder - in real implementation, you would:
    // 1. Use Seal's decryption functions to decrypt sealed_data
    // 2. Parse the decrypted JSON/data to extract question and options

    // For now, return mock data
    let question_text = string::utf8(b"Sample Question?");
    let mut options = vector::empty();
    vector::push_back(&mut options, string::utf8(b"Option A"));
    vector::push_back(&mut options, string::utf8(b"Option B"));
    vector::push_back(&mut options, string::utf8(b"Option C"));
    vector::push_back(&mut options, string::utf8(b"Option D"));

    (question_text, options)
}

// ======== View Functions ========

/// Get room information
public fun get_room_info(room: &GameRoom): (String, String, u8, u64, u64, u64) {
    (
        room.title,
        room.description,
        room.status,
        vector::length(&room.participant_addresses),
        room.max_participants,
        vector::length(&room.encrypted_questions),
    )
}

/// Get current question if revealed
public fun get_current_question(room: &GameRoom): (String, vector<String>, u64) {
    assert!(
        table::contains(&room.revealed_questions, room.current_question_index),
        EQuestionNotActive,
    );

    let question = table::borrow(&room.revealed_questions, room.current_question_index);
    (question.text, question.options, room.question_start_time)
}

/// Get participant score
public fun get_participant_score(room: &GameRoom, participant: address): u64 {
    assert!(table::contains(&room.participants, participant), ENotParticipant);
    let p = table::borrow(&room.participants, participant);
    p.total_score
}

/// Get leaderboard
public fun get_leaderboard(room: &GameRoom): vector<LeaderboardEntry> {
    room.leaderboard
}

/// Check if participant has answered current question
public fun has_answered_current_question(room: &GameRoom, participant: address): bool {
    if (!table::contains(&room.participants, participant)) {
        return false
    };

    let p = table::borrow(&room.participants, participant);
    table::contains(&p.answers, room.current_question_index)
}

// ======== Utility Functions ========

/// Create a new encrypted question
public fun new_encrypted_question(walrus_hash: String): EncryptedQuestion {
    EncryptedQuestion {
        walrus_hash,
    }
}

/// Helper function to create room and handle sharing
public fun create_room_and_cap(
    title: String,
    description: String,
    encrypted_questions: vector<EncryptedQuestion>,
    max_participants: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (room, creator_cap) = create_room(
        title,
        description,
        encrypted_questions,
        max_participants,
        clock,
        ctx,
    );

    transfer::share_object(room);
    transfer::transfer(creator_cap, ctx.sender());
}

entry fun seal_approve(id: address, ctx: &mut TxContext) {
    assert!(ctx.sender() == id, ENoAccess);
}
