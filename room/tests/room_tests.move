#[test_only]
module room::room_tests;

use room::room::{Self, GameRoom, CreatorCap, EncryptedQuestion};
use std::string;
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self as ts, Scenario};

const CREATOR: address = @0xABCD;
const PLAYER1: address = @0x1111;
const PLAYER2: address = @0x2222;

#[test]
fun test_create_room() {
    let mut scenario = ts::begin(CREATOR);
    let ctx = ts::ctx(&mut scenario);

    // Create clock
    let clock = clock::create_for_testing(ctx);

    // Create sample encrypted questions
    let mut questions = vector::empty<EncryptedQuestion>();
    vector::push_back(
        &mut questions,
        room::new_encrypted_question(
            string::utf8(b"walrus_hash_1"),
            vector[1, 2, 3, 4], // mock encrypted data
            vector[5, 6, 7, 8], // mock answer hash
            100,
        ),
    );

    // Create room
    let (room, creator_cap) = room::create_room(
        string::utf8(b"Test Room"),
        string::utf8(b"A test room for testing"),
        questions,
        10,
        &clock,
        ctx,
    );

    // Verify room creation
    let (title, description, status, participants, max_p, total_q) = room::get_room_info(&room);
    assert!(title == string::utf8(b"Test Room"), 0);
    assert!(description == string::utf8(b"A test room for testing"), 1);
    assert!(status == 0, 2); // Open status
    assert!(participants == 0, 3);
    assert!(max_p == 10, 4);
    assert!(total_q == 1, 5);

    // Clean up
    transfer::public_share_object(room);
    transfer::public_transfer(creator_cap, CREATOR);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_join_room() {
    let mut scenario = ts::begin(CREATOR);

    // Create room as creator
    ts::next_tx(&mut scenario, CREATOR);
    {
        let ctx = ts::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        let mut questions = vector::empty<EncryptedQuestion>();
        vector::push_back(
            &mut questions,
            room::new_encrypted_question(
                string::utf8(b"walrus_hash_1"),
                vector[1, 2, 3, 4],
                vector[5, 6, 7, 8],
                100,
            ),
        );

        let (room, creator_cap) = room::create_room(
            string::utf8(b"Test Room"),
            string::utf8(b"Test Description"),
            questions,
            10,
            &clock,
            ctx,
        );

        transfer::public_share_object(room);
        transfer::public_transfer(creator_cap, CREATOR);
        clock::destroy_for_testing(clock);
    };

    // Player joins room
    ts::next_tx(&mut scenario, PLAYER1);
    {
        let mut room = ts::take_shared<GameRoom>(&scenario);
        let ctx = ts::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        room::join_room(&mut room, &clock, ctx);

        let (_, _, _, participants, _, _) = room::get_room_info(&room);
        assert!(participants == 1, 0);

        ts::return_shared(room);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
fun test_game_flow() {
    let mut scenario = ts::begin(CREATOR);

    // Create room
    ts::next_tx(&mut scenario, CREATOR);
    {
        let ctx = ts::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        let mut questions = vector::empty<EncryptedQuestion>();
        vector::push_back(
            &mut questions,
            room::new_encrypted_question(
                string::utf8(b"walrus_hash_1"),
                vector[1, 2, 3, 4],
                vector[5, 6, 7, 8], // This will be the correct answer hash
                100,
            ),
        );

        let (room, creator_cap) = room::create_room(
            string::utf8(b"Test Game"),
            string::utf8(b"Test Game Description"),
            questions,
            5,
            &clock,
            ctx,
        );

        transfer::public_share_object(room);
        transfer::public_transfer(creator_cap, CREATOR);
        clock::destroy_for_testing(clock);
    };

    // Players join
    ts::next_tx(&mut scenario, PLAYER1);
    {
        let mut room = ts::take_shared<GameRoom>(&scenario);
        let ctx = ts::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        room::join_room(&mut room, &clock, ctx);

        ts::return_shared(room);
        clock::destroy_for_testing(clock);
    };

    ts::next_tx(&mut scenario, PLAYER2);
    {
        let mut room = ts::take_shared<GameRoom>(&scenario);
        let ctx = ts::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        room::join_room(&mut room, &clock, ctx);

        ts::return_shared(room);
        clock::destroy_for_testing(clock);
    };

    // Start game
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut room = ts::take_shared<GameRoom>(&scenario);
        let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);
        let ctx = ts::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        room::start_game(&mut room, &creator_cap, &clock, ctx);

        let (_, _, status, _, _, _) = room::get_room_info(&room);
        assert!(status == 1, 0); // Started status

        ts::return_shared(room);
        ts::return_to_sender(&scenario, creator_cap);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}
