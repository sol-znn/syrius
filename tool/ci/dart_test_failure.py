"""Project known test locations and fixed assertion labels without raw errors."""

import json
import re

FILES = ('wallet_tour_test.dart', 'build_output_test.dart',
    'copied_wallet_pointer.dart', 'copied_wallet_pointer_test.dart',
    'ci_copied_wallet_pointer.dart', 'copied_pointer_input_test.dart',
    'ci_wallet_reopen.dart', 'restored_startup_test.dart',
    'restored_unlock_ready_test.dart',
    'lock_view_observation_test.dart', 'lock_view_observation.dart',
    'import_selector_metrics_test.dart',
    'lock_tab_child.dart',
    'welcome_drop_route_test.dart', 'welcome_surface_test.dart',
    'restored_seed_workflow.dart', 'restored_seed_workflow_test.dart',
    'lab_quiescence.dart', 'lab_quiescence_test.dart',
    'wallet_address_recipe_test.dart', 'addresses_selection_test.dart',
    'lab_transfer_witness_test.dart', 'lab_transfer_witness.dart',
    'lab_send_policy_test.dart', 'lab_send_journal_test.dart',
    'lab_send_ui_binding.dart', 'lab_send_ui_binding_test.dart',
    'lab_send_failure.dart', 'lab_send_failure_test.dart',
    'lab_sender_menu_test.dart', 'transfer_sender_header_test.dart',
    'startup_key_confirm_test.dart', 'startup_key_refusal_test.dart',
    'startup_key_support.dart', 'launch_film_test.dart',
    'send_populated.dart',
    'lab_send_policy.dart', 'seed_policy_test.dart', 'seed_policy.dart',
    'lab_seed_binding.dart',
    'seed_preparation_failure.dart',
    'selection_context_revision_test.dart', 'default_address_notifier.dart',
    'recipe_control_admission_test.dart', 'recipe_control_admission.dart',
    'wallet_recipe_failure_test.dart', 'wallet_recipe_startup_test.dart',
    'wallet_recipe_test.dart', 'key_dispatch_test.dart', 'rail_navigation_test.dart', 'agent.dart',
    'launch_film.dart', 'startup_stage.dart',
    'entry_capture_source_test.dart', 'entry_capture_opt_in_test.dart',
    'entry_prepared_draft_test.dart', 'entry_capture_source.dart',
    'import_wallet_seed_choice_screen.dart', 'native_entry_capture.dart',
    'retained_png.dart', 'retained_renderer_frame.dart',
    'readonly_sdk_admission.dart', 'readonly_sdk_binding.dart',
    'readonly_native_commands.dart', 'readonly_native_mode.dart',
    'readonly_wallet_admission.dart', 'readonly_wallet_binding.dart',
    'readonly_wallet_admission_test.dart',
    'readonly_inspection_session.dart', 'readonly_inspection_session_test.dart',
    'readonly_viewport_probe.dart',
    'ci_wallet_inspection.dart',
    'launch_decode_observation_test.dart')
# The root baseline also runs suites outside the focused harness. These
# labels are versioned test basenames, never names taken from error text.
ROOT_TEST_FILES = (
    'about_information_test.dart',
    'about_settings_view_test.dart',
    'accelerator_action_binding_test.dart',
    'accelerator_action_controller_test.dart',
    'accelerator_bloc_lifecycle_test.dart',
    'accelerator_list_presenter_test.dart',
    'accelerator_list_view_test.dart',
    'accelerator_project_cache_test.dart',
    'accelerator_project_presenter_test.dart',
    'accelerator_project_view_test.dart',
    'accelerator_vote_policy_test.dart',
    'accepted_recipient_test.dart',
    'access_lifecycle_test.dart',
    'account_block_session_test.dart',
    'active_pillars_cubit_test.dart',
    'active_sentinels_cubit_test.dart',
    'activity_entry_test.dart',
    'activity_row_test.dart',
    'address_generation_test.dart',
    'address_owned_fetch_test.dart',
    'addresses_presenter_test.dart',
    'addresses_selection_test.dart',
    'addresses_view_test.dart',
    'agent_input_test.dart',
    'amount_input_test.dart',
    'app_lottie_rules_test.dart',
    'app_lottie_test.dart',
    'app_tokens_interpolation_test.dart',
    'app_tokens_test.dart',
    'apps_settings_presenter_test.dart',
    'apps_settings_view_test.dart',
    'auto_receive_tx_worker_test.dart',
    'auto_unlock_ownership_test.dart',
    'background_crypto_test.dart',
    'balance_cubit_test.dart',
    'bell_controller_test.dart',
    'bell_panel_test.dart',
    'bell_storage_test.dart',
    'bounded_history_test.dart',
    'build_output_test.dart',
    'bundled_fonts_test.dart',
    'burn_token_bloc_test.dart',
    'cache_policy_test.dart',
    'cancel_plasma_bloc_test.dart',
    'cancel_stake_bloc_test.dart',
    'capture_frame_test.dart',
    'capture_protocol_test.dart',
    'captured_sender_test.dart',
    'card_token_ink_test.dart',
    'chain_explorer_test.dart',
    'client_window_agent_test.dart',
    'client_window_test.dart',
    'contacts_store_test.dart',
    'copied_pointer_input_test.dart',
    'copied_wallet_pointer_test.dart',
    'create_pillar_qsr_info_bloc_test.dart',
    'create_sentinel_qsr_info_bloc_test.dart',
    'create_stake_card_test.dart',
    'creation_route_ownership_test.dart',
    'custom_material_stepper_test.dart',
    'dapp_bridge_app_test.dart',
    'dapp_bridge_channel_test.dart',
    'dapp_bridge_origin_test.dart',
    'dapp_bridge_parity_test.dart',
    'dapp_bridge_server_test.dart',
    'dapp_bridge_service_test.dart',
    'dapp_bridge_widgets_test.dart',
    'dapp_consent_receipt_test.dart',
    'delegation_bloc_test.dart',
    'delegation_stats_bloc_test.dart',
    'deploy_pillar_bloc_test.dart',
    'deploy_sentinel_bloc_test.dart',
    'devnet_deposit_confirmation_test.dart',
    'devnet_pillar_observation_test.dart',
    'devnet_registration_host_test.dart',
    'devnet_stake_host_test.dart',
    'devnet_token_stepper_form_test.dart',
    'devnet_wallet_binding_test.dart',
    'dialog_motion_test.dart',
    'disclosure_test.dart',
    'display_settings_test.dart',
    'dollar_text_test.dart',
    'dual_coin_stats_cubit_test.dart',
    'durable_action_test.dart',
    'embedded_node_test.dart',
    'entry_action_boundary_test.dart',
    'entry_caption_observer_test.dart',
    'entry_capture_opt_in_test.dart',
    'entry_capture_progress_test.dart',
    'entry_capture_source_test.dart',
    'entry_chrome_test.dart',
    'entry_field_test.dart',
    'entry_prepared_draft_test.dart',
    'event_toast_test.dart',
    'exact_height_test.dart',
    'explorer_links_test.dart',
    'favorite_ordering_test.dart',
    'favorite_tokens_repository_test.dart',
    'fetch_bloc_test.dart',
    'fixture_cleanup_test.dart',
    'flight_state_test.dart',
    'font_fallback_test.dart',
    'frosted_route_test.dart',
    'frosted_surface_test.dart',
    'fuse_plasma_bloc_test.dart',
    'fuse_plasma_card_test.dart',
    'fuse_plasma_form_test.dart',
    'fused_plasma_bloc_test.dart',
    'fusions_follow_up_test.dart',
    'general_stats_bloc_test.dart',
    'go_to_catalog_test.dart',
    'go_to_palette_test.dart',
    'handler_ownership_test.dart',
    'handler_replay_test.dart',
    'handler_start_ownership_test.dart',
    'hidden_balances_test.dart',
    'hive_adapters_test.dart',
    'home_collection_controller_test.dart',
    'home_cubit_test.dart',
    'home_hero_test.dart',
    'home_side_cards_test.dart',
    'import_decrypt_attempt_test.dart',
    'import_draft_test.dart',
    'import_file_offer_test.dart',
    'import_selector_metrics_test.dart',
    'import_surface_test.dart',
    'infinite_list_bloc_test.dart',
    'initial_join_proof_test.dart',
    'is_key_store_file_test.dart',
    'issue_token_bloc_test.dart',
    'issue_token_step_test.dart',
    'key_dispatch_test.dart',
    'lab_quiescence_test.dart',
    'lab_send_failure_test.dart',
    'lab_send_journal_test.dart',
    'lab_send_policy_test.dart',
    'lab_send_ui_binding_test.dart',
    'lab_sender_menu_test.dart',
    'lab_transfer_witness_test.dart',
    'language_setting_test.dart',
    'latest_transactions_bloc_test.dart',
    'latest_transactions_card_test.dart',
    'launch_asset_test.dart',
    'launch_decode_observation_test.dart',
    'launch_film_test.dart',
    'launch_webp_frames_test.dart',
    'legacy_guard_lifecycle_test.dart',
    'licences_test.dart',
    'list_entrance_test.dart',
    'locale_formats_test.dart',
    'lock_attempt_bookkeeping_test.dart',
    'lock_card_test.dart',
    'lock_view_observation_test.dart',
    'logical_capture_test.dart',
    'ltr_test.dart',
    'mint_token_bloc_test.dart',
    'missing_services_test.dart',
    'mockup_tokens_test.dart',
    'motion_binding_test.dart',
    'multiple_balance_bloc_test.dart',
    'native_entry_command_test.dart',
    'native_window_owner_test.dart',
    'neutral_button_geometry_test.dart',
    'node_chain_read_test.dart',
    'node_change_test.dart',
    'node_collection_controller_test.dart',
    'node_library_test.dart',
    'node_owner_publisher_test.dart',
    'node_settings_presenter_test.dart',
    'node_settings_view_test.dart',
    'node_sync_status_cubit_test.dart',
    'node_transition_test.dart',
    'node_update_card_test.dart',
    'node_update_cubit_test.dart',
    'node_updater_test.dart',
    'nodes_counts_cubit_test.dart',
    'nodes_delegation_test.dart',
    'nodes_page_test.dart',
    'nodes_rewards_test.dart',
    'notification_overlay_test.dart',
    'notification_persistence_test.dart',
    'notification_writer_test.dart',
    'onboarding_transition_test.dart',
    'original_actions_test.dart',
    'original_publications_test.dart',
    'originals_test.dart',
    'page_actions_test.dart',
    'page_strip_test.dart',
    'palette_surface_test.dart',
    'panel_collapse_test.dart',
    'panel_test.dart',
    'peer_count_test.dart',
    'pending_approval_test.dart',
    'pending_transactions_bloc_test.dart',
    'pillar_deposit_qsr_bloc_test.dart',
    'pillar_list_data_test.dart',
    'pillar_owner_card_test.dart',
    'pillar_owner_panel_test.dart',
    'pillar_owner_snapshot_test.dart',
    'pillar_rewards_history_bloc_test.dart',
    'pillar_withdraw_qsr_bloc_test.dart',
    'pillars_bloc_test.dart',
    'pillars_by_owner_bloc_test.dart',
    'pillars_card_test.dart',
    'plasma_cancellation_test.dart',
    'plasma_fuse_hold_test.dart',
    'plasma_fuse_test.dart',
    'plasma_lifecycle_test.dart',
    'plasma_list_test.dart',
    'plasma_meter_test.dart',
    'plasma_purpose_test.dart',
    'plasma_read_test.dart',
    'plasma_transport_test.dart',
    'plasma_well_test.dart',
    'pow_generating_status_bloc_test.dart',
    'pre_decrypt_capability_test.dart',
    'preparation_ownership_test.dart',
    'presentation_close_test.dart',
    'presentation_host_test.dart',
    'presentation_mode_test.dart',
    'price_feed_test.dart',
    'primary_pill_test.dart',
    'project_list_bloc_test.dart',
    'publication_admission_test.dart',
    'queued_generation_test.dart',
    'rail_navigation_test.dart',
    'rail_test.dart',
    'read_ownership_test.dart',
    'readonly_inspection_session_test.dart',
    'readonly_native_agent_test.dart',
    'readonly_native_commands_test.dart',
    'readonly_native_mode_test.dart',
    'readonly_sdk_admission_test.dart',
    'readonly_sdk_binding_test.dart',
    'readonly_viewport_probe_test.dart',
    'readonly_wallet_admission_test.dart',
    'realtime_statistics_cubit_test.dart',
    'receive_cell_test.dart',
    'receive_drain_test.dart',
    'receive_feed_test.dart',
    'receive_origin_test.dart',
    'receive_populated_test.dart',
    'receive_qr_image_test.dart',
    'receive_request_test.dart',
    'receive_transaction_cubit_test.dart',
    'recipe_control_admission_test.dart',
    'reference_artwork_owner_test.dart',
    'refresh_subscription_test.dart',
    'registration_confirmation_test.dart',
    'registration_originals_test.dart',
    'registration_publisher_test.dart',
    'registration_success_surface_test.dart',
    'resource_guard_test.dart',
    'restored_seed_workflow_test.dart',
    'restored_startup_test.dart',
    'restored_unlock_ready_test.dart',
    'retained_forms_test.dart',
    'retained_renderer_frame_test.dart',
    'revoke_pillar_bloc_test.dart',
    'revoke_sentinel_bloc_test.dart',
    'revoke_sentinel_button_test.dart',
    'rise_switcher_test.dart',
    'row_detail_test.dart',
    'screen_capture_test.dart',
    'seam_gate_test.dart',
    'seams_document_test.dart',
    'search_token_bloc_test.dart',
    'security_settings_presenter_test.dart',
    'security_settings_view_test.dart',
    'seed_deposit_entry_test.dart',
    'seed_deposit_presentation_test.dart',
    'seed_fixture_admission_test.dart',
    'seed_policy_test.dart',
    'seed_quiz_surface_test.dart',
    'seed_quiz_test.dart',
    'seed_recipe_test.dart',
    'segment_availability_test.dart',
    'segment_counts_test.dart',
    'segment_heading_test.dart',
    'segment_test.dart',
    'select_file_refusal_test.dart',
    'selection_context_revision_test.dart',
    'semantic_theme_test.dart',
    'send_confirmation_flow_test.dart',
    'send_draft_cubit_test.dart',
    'send_form_test.dart',
    'send_intent_test.dart',
    'send_transaction_bloc_test.dart',
    'sender_admission_test.dart',
    'sent_notification_title_test.dart',
    'sentinel_deposit_qsr_bloc_test.dart',
    'sentinel_rewards_history_bloc_test.dart',
    'sentinel_stats_card_test.dart',
    'sentinel_strip_test.dart',
    'sentinel_values_test.dart',
    'sentinel_withdraw_qsr_bloc_test.dart',
    'sentinels_bloc_test.dart',
    'sentinels_by_owner_bloc_test.dart',
    'sentinels_card_test.dart',
    'service_lifetime_test.dart',
    'settings_frame_test.dart',
    'settings_sensitive_actions_test.dart',
    'settings_sensitive_routes_test.dart',
    'settings_switch_test.dart',
    'shader_clock_test.dart',
    'shared_widget_tokens_test.dart',
    'shared_widgets_l10n_test.dart',
    'sheen_test.dart',
    'shell_frame_test.dart',
    'shortcuts_test.dart',
    'skeleton_test.dart',
    'slider_setting_test.dart',
    'stakes_bloc_test.dart',
    'stakes_card_test.dart',
    'staking_cubit_test.dart',
    'staking_page_test.dart',
    'staking_rewards_history_bloc_test.dart',
    'startup_cleanup_receipt_test.dart',
    'startup_key_confirm_test.dart',
    'startup_key_refusal_test.dart',
    'startup_stage_test.dart',
    'step_switcher_test.dart',
    'store_ownership_test.dart',
    'store_reentrant_ownership_test.dart',
    'strip_test.dart',
    'swap_action_boundary_test.dart',
    'swap_action_data_test.dart',
    'swap_list_presenter_test.dart',
    'swap_list_transport_test.dart',
    'swap_list_view_test.dart',
    'swap_modal_ownership_test.dart',
    'swap_transfer_surface_test.dart',
    'switch_theme_test.dart',
    'sync_pulse_test.dart',
    'table_entrance_test.dart',
    'theme_control_test.dart',
    'timer_cubit_test.dart',
    'toast_utils_test.dart',
    'token_action_publisher_test.dart',
    'token_action_session_test.dart',
    'token_balance_reader_test.dart',
    'token_card_test.dart',
    'token_create_frame_test.dart',
    'token_create_preflight_test.dart',
    'token_create_publisher_test.dart',
    'token_create_transport_test.dart',
    'token_create_view_test.dart',
    'token_facts_test.dart',
    'token_favorite_bloc_test.dart',
    'token_inline_actions_test.dart',
    'token_map_bloc_test.dart',
    'token_metrics_step_test.dart',
    'token_row_action_test.dart',
    'tokens_bloc_test.dart',
    'tokens_view_test.dart',
    'total_hourly_transactions_cubit_test.dart',
    'transfer_page_test.dart',
    'transfer_sender_header_test.dart',
    'transfer_token_bloc_test.dart',
    'ui_isolate_test.dart',
    'uncollected_pillar_rewards_bloc_test.dart',
    'uncollected_sentinel_rewards_bloc_test.dart',
    'uncollected_staking_rewards_bloc_test.dart',
    'undelegate_bloc_test.dart',
    'update_pillar_bloc_test.dart',
    'update_slot_test.dart',
    'usd_format_test.dart',
    'utils_l10n_test.dart',
    'validators_l10n_test.dart',
    'value_flash_test.dart',
    'wallet_action_context_test.dart',
    'wallet_address_recipe_test.dart',
    'wallet_connect_input_lifecycle_test.dart',
    'wallet_file_probe_test.dart',
    'wallet_flight_registry_test.dart',
    'wallet_initialization_target_test.dart',
    'wallet_initialization_test.dart',
    'wallet_lock_attempt_test.dart',
    'wallet_maintenance_backend_capture_test.dart',
    'wallet_maintenance_resources_test.dart',
    'wallet_maintenance_test.dart',
    'wallet_picker_test.dart',
    'wallet_ready_capture_test.dart',
    'wallet_ready_test.dart',
    'wallet_recipe_failure_test.dart',
    'wallet_recipe_startup_test.dart',
    'wallet_recipe_test.dart',
    'wallet_settings_presenter_test.dart',
    'wallet_settings_resources_test.dart',
    'wallet_settings_view_test.dart',
    'wallet_sign_original_test.dart',
    'wallet_tour_test.dart',
    'web3_original_actions_test.dart',
    'welcome_drop_route_test.dart',
    'welcome_surface_test.dart',
    'window_chrome_test.dart',
    'window_frame_test.dart',
    'withdrawal_proof_test.dart',
    'zap_draft_test.dart',
    'zap_form_test.dart',
    'zap_sparks_test.dart',
)
FILES = tuple(dict.fromkeys((*FILES, *ROOT_TEST_FILES)))


CATEGORIES = (
    (r'Failed to load', 'LOAD_ERROR'),
    (r'MissingPluginException', 'MISSING_PLUGIN'),
    (r'Null check operator used on a null value', 'NULL_CHECK'),
    (r'TypeError|is not a subtype', 'TYPE_ERROR'),
    (r'TimeoutException|[Tt]est timed out', 'TIMEOUT'),
    (r'A RenderFlex overflowed|RenderBox was not laid out|BoxConstraints forces', 'LAYOUT'),
    (r'[Tt]imer is still pending|Pending timers:', 'PENDING_TIMER'),
    (r'used after being disposed', 'DISPOSED'),
    (r'TestFailure|Expected:|assertion was thrown|Assertion failed:', 'ASSERTION'),
    (r'EXCEPTION CAUGHT', 'FRAMEWORK'),
)

FRAMEWORK_ASSERTIONS = {
    'package:flutter/src/widgets/framework.dart': 'flutter_framework',
    'package:flutter/src/rendering/object.dart': 'flutter_render_object',
    'package:flutter/src/rendering/box.dart': 'flutter_box',
    'package:flutter/src/material/dropdown.dart': 'flutter_dropdown',
    'package:flutter/src/material/dropdown_menu.dart': 'flutter_dropdown_menu',
    'package:flutter/src/foundation/change_notifier.dart': 'flutter_notifier',
    'package:flutter/src/widgets/scroll_controller.dart': 'flutter_scroll',
    'package:flutter/src/widgets/binding.dart': 'flutter_widgets_binding',
    'package:flutter/src/scheduler/binding.dart': 'flutter_scheduler_binding',
    'package:provider/src/provider.dart': 'provider_core',
    'package:provider/src/inherited_provider.dart': 'provider_inherited',
    'package:flutter_bloc/src/bloc_builder.dart': 'flutter_bloc_builder',
    'package:flutter_bloc/src/bloc_provider.dart': 'flutter_bloc_provider',
    'package:bloc/src/emitter.dart': 'bloc_emitter',
    'package:get_it/get_it_impl.dart': 'get_it_registry',
    'package:flutter_test/src/binding.dart': 'flutter_test_binding',
    'package:flutter_test/src/widget_tester.dart': 'flutter_widget_tester',
    'package:flutter_test/src/test_async_utils.dart': 'flutter_test_async',
    'package:flutter_test/src/async_matchers.dart': 'flutter_test_matchers',
}
FRAMEWORK_FAILURE_KINDS = ('FLUTTER_ERROR', 'ASSERTION_ERROR', 'STATE_ERROR',
    'TYPE_ERROR', 'NO_SUCH_METHOD', 'FORMAT_ERROR', 'OTHER')


def framework_assertion(text, stack=''):
    """Keep only an allowlisted package label and bounded numeric position."""
    found = []
    for path, label in FRAMEWORK_ASSERTIONS.items():
        match = re.search(r'''['"]''' + re.escape(path)
            + r'''['"]:\s*Failed assertion:\s*line\s+([1-9][0-9]{0,5})'''
            + r'\s+pos\s+([1-9][0-9]{0,5})(?![0-9])', text)
        if match:
            found.append((match.start(), label, int(match[1]), int(match[2])))
    if found:
        _, source, line, column = min(found)
        return dict(source=source, line=line, column=column)
    # FlutterError.fromParts may have no native assertion header. An owned
    # package frame is context, not proof of the exact assertion origin.
    context = stack + '\n' + text
    for path, label in FRAMEWORK_ASSERTIONS.items():
        match = re.search(r'\(' + re.escape(path)
            + r':([1-9][0-9]{0,5}):([1-9][0-9]{0,5})\)', context)
        if match:
            found.append((match.start(), label, int(match[1]), int(match[2])))
    if found:
        _, source, line, column = min(found)
        return dict(source=source, line=line, column=column, kind='STACK_FRAME')
    return None


def location(text, *, tests_only=False):
    found = []
    for name in FILES:
        if tests_only and not name.endswith('_test.dart'):
            continue
        match = re.search(r'(?<![A-Za-z0-9_.-])' + re.escape(name)
            + r'(?::|\s+)([1-9][0-9]{0,5})(?![0-9])(?::[0-9]+)?', text)
        if match:
            found.append((match.start(), name, int(match[1])))
    return min(found) if found else None


def project(raw):
    refused = dict(status='REFUSED', total=0, items=[])
    if type(raw) is not bytes or len(raw) > 4 * 1024**2:
        return refused
    lines = raw.splitlines()
    if len(lines) > 20000:
        return refused
    total, items, prints = 0, [], {}
    suites, tests = {}, {}
    try:
        for line in lines:
            if not line.strip():
                continue
            event = json.loads(line)
            if type(event) is not dict:
                return refused
            if event.get('type') == 'suite':
                suite = event.get('suite')
                if (type(suite) is not dict or type(suite.get('id')) is not int
                        or not 0 <= suite['id'] <= 20000
                        or suite['id'] in suites or len(suites) >= 1024):
                    return refused
                path = suite.get('path')
                name = (path.replace('\\', '/').rsplit('/', 1)[-1]
                        if type(path) is str and len(path) <= 4096 else None)
                suites[suite['id']] = name if name in ROOT_TEST_FILES else None
                continue
            if event.get('type') == 'testStart':
                test = event.get('test')
                if (type(test) is not dict or type(test.get('id')) is not int
                        or not 0 <= test['id'] <= 20000
                        or type(test.get('suiteID')) is not int
                        or test['id'] in tests or len(tests) >= 20000):
                    return refused
                tests[test['id']] = suites.get(test['suiteID'])
                continue
            if event.get('type') == 'print':
                identity, message = event.get('testID'), event.get('message')
                if type(identity) is int and identity >= 0 and event.get('messageType', 'print') == 'print':
                    if type(message) is not str:
                        return refused
                    if identity not in prints and len(prints) >= 256:
                        return refused
                    prints[identity] = (prints.get(identity, '') + '\n' + message)[-16384:]
                continue
            if event.get('type') != 'error':
                continue
            error, stack = event.get('error'), event.get('stackTrace')
            failure = event.get('isFailure')
            if type(error) is not str or type(stack) is not str or type(failure) is not bool:
                return refused
            total += 1
            if len(items) == 3:
                continue
            identity = event.get('testID')
            context = prints.get(identity, '') if type(identity) is int else ''
            details = error + '\n' + context
            source, selected = 'NONE', None
            for label, text in (('STACK', stack), ('ERROR', error), ('PRINT', context)):
                selected = location(text)
                if selected:
                    source = label
                    break
            expectation = 'OTHER'
            for pattern, label in ((r'Expected:\s*true\b', 'TRUE'),
                                   (r'Expected:\s*false\b', 'FALSE'),
                                   (r'Expected:\s*<1>(?:\s|$)', 'ONE')):
                if re.search(pattern, details):
                    expectation = label
                    break
            category = next((label for pattern, label in CATEGORIES
                if re.search(pattern, details)), 'OTHER')
            item = dict(file=selected[1] if selected else None,
                line=selected[2] if selected else None, location_source=source,
                kind='ASSERTION' if failure else 'UNHANDLED',
                expectation=expectation, category=category)
            suite = tests.get(identity) if type(identity) is int else None
            if suite is not None:
                item['suite_file'] = suite
            for label, text in (('STACK', stack), ('ERROR', error), ('PRINT', context)):
                caller = location(text, tests_only=True)
                if caller is not None:
                    if selected is not None and caller[1:] != selected[1:]:
                        item['test_context'] = dict(file=caller[1], line=caller[2],
                            location_source=label)
                    break
            assertion = framework_assertion(details, stack)
            if assertion is not None:
                item['framework_assertion'] = assertion
            marker = re.search(r'(?m)^CI_FRAMEWORK_FAILURE_KIND:('
                + '|'.join(FRAMEWORK_FAILURE_KINDS) + r')\r?$', context)
            if marker:
                item['framework_failure_kind'] = marker[1]
            items.append(item)
    except (ValueError, UnicodeError, TypeError):
        return refused
    return dict(status='OBSERVED' if total else 'NO_ERROR_EVENTS', total=total, items=items)



def locations_projection(value):
    """Validate only fixed source labels; no original error or test text."""
    if not (type(value) is dict and set(value) == {'status', 'total', 'items'}
            and type(value['status']) is str
            and value['status'] in ('OBSERVED', 'NO_ERROR_EVENTS', 'REFUSED')
            and type(value['total']) is int and 0 <= value['total'] <= 20000
            and type(value['items']) is list):
        return None
    observed = value['status'] == 'OBSERVED'
    if ((value['total'] > 0) != observed or
            len(value['items']) != (min(value['total'], 3) if observed else 0)):
        return None
    result = []
    for item in value['items']:
        if not (type(item) is dict and set(item) in (
                    {'file', 'line', 'kind', 'category'},
                    {'file', 'line', 'kind', 'category', 'suite_file'})
                and ((item['file'] is None and item['line'] is None) or
                     type(item['file']) is str and item['file'] in FILES
                     and type(item['line']) is int and 0 < item['line'] <= 999999)
                and type(item['kind']) is str and item['kind'] in ('ASSERTION', 'UNHANDLED')
                and type(item['category']) is str
                and item['category'] in {label for _, label in CATEGORIES} | {'OTHER'}):
            return None
        if ('suite_file' in item and (type(item['suite_file']) is not str
                or item['suite_file'] not in ROOT_TEST_FILES)):
            return None
        result.append(dict(item))
    return dict(status=value['status'], total=value['total'], items=result)


def locations(raw):
    """Project capped original JSON events to at most three source locations."""
    value = project(raw)
    compact = dict(value, items=[{
        **{key: item[key] for key in ('file', 'line', 'kind', 'category')},
        **({'suite_file': item['suite_file']} if 'suite_file' in item else {}),
    } for item in value['items']])
    projected = locations_projection(compact)
    return projected if projected is not None else dict(status='REFUSED', total=0, items=[])
