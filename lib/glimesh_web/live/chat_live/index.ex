defmodule GlimeshWeb.ChatLive.Index do
  use GlimeshWeb, :live_view

  alias Glimesh.Accounts
  alias Glimesh.ChannelLookups
  alias Glimesh.Chat
  alias Glimesh.Chat.ChatMessage
  alias Glimesh.Presence
  alias Glimesh.Streams
  alias Glimesh.Streams.Channel

  @impl true
  def mount(_params, %{"channel_id" => channel_id} = session, socket) do
    if session["locale"], do: Gettext.put_locale(session["locale"])
    if connected?(socket), do: Streams.subscribe_to(:chat, channel_id)

    channel = ChannelLookups.get_channel!(channel_id)

    # Sets a default user_preferences map for the chat if the user is logged out
    user_preferences =
      if session["user"] do
        Accounts.get_user_preference!(session["user"])
      else
        %{
          show_timestamps: false,
          show_mod_icons: false
        }
      end

    if session["user"] do
      user = session["user"]

      Presence.track_presence(
        self(),
        Streams.get_subscribe_topic(:chatters, channel.id),
        user.id,
        %{
          typing: false,
          username: user.username,
          avatar: Glimesh.Avatar.url({user.avatar, user}, :original),
          user_id: user.id,
          size: 48
        }
      )
    end

    new_socket =
      socket
      |> assign(:channel_chat_parser_config, Chat.get_chat_parser_config(channel))
      |> assign(:update_action, "replace")
      |> assign(:channel, channel)
      |> assign(:user, session["user"])
      |> assign(:theme, Map.get(session, "site_theme", "dark"))
      |> assign(:permissions, Chat.get_moderator_permissions(channel, session["user"]))
      |> assign(:chat_messages, list_chat_messages(channel))
      |> assign(:chat_message, %ChatMessage{})
      |> assign(:show_timestamps, user_preferences.show_timestamps)
      |> assign(:show_mod_icons, user_preferences.show_mod_icons)
      |> assign(:user_preferences, user_preferences)
      |> assign(:popped_out, Map.get(session, "popped_out", false))

    {:ok, new_socket, temporary_assigns: [chat_messages: []]}
  end

  @impl true
  def handle_event("scroll_to_bottom", _, socket) do
    {:noreply, push_event(socket, "scroll_to_bottom", %{})}
  end

  @impl true
  def handle_event("short_timeout_user", %{"user" => to_ban_user}, socket) do
    Chat.short_timeout_user(
      socket.assigns.user,
      socket.assigns.channel,
      Accounts.get_by_username!(to_ban_user, true)
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("long_timeout_user", %{"user" => to_ban_user}, socket) do
    Chat.long_timeout_user(
      socket.assigns.user,
      socket.assigns.channel,
      Accounts.get_by_username!(to_ban_user, true)
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("ban_user", %{"user" => to_ban_user}, socket) do
    Chat.ban_user(
      socket.assigns.user,
      socket.assigns.channel,
      Accounts.get_by_username!(to_ban_user, true)
    )

    {:noreply, assign(socket, :chat_messages, list_chat_messages(socket.assigns.channel))}
  end

  @impl true
  def handle_event("delete_message", %{"message" => message_id, "user" => message_author}, socket) do
    chat_message = Chat.get_chat_message!(message_id)

    Chat.delete_message(
      socket.assigns.user,
      socket.assigns.channel,
      Accounts.get_by_username!(message_author, true),
      chat_message
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_timestamps", params, socket) when map_size(params) == 0 do
    timestamp_state = Kernel.not(socket.assigns.show_timestamps)

    {:noreply,
     socket
     |> assign(:show_timestamps, timestamp_state)
     |> assign(:user_preferences, %{show_timestamps: timestamp_state})
     |> push_event("toggle_timestamps", %{
       show_timestamps: timestamp_state
     })}
  end

  @impl true
  def handle_event("toggle_timestamps", %{"user" => _username}, socket) do
    timestamp_state = Kernel.not(socket.assigns.show_timestamps)

    {:ok, user_preferences} =
      Accounts.update_user_preference(socket.assigns.user_preferences, %{
        show_timestamps: timestamp_state
      })

    {:noreply,
     socket
     |> assign(:show_timestamps, timestamp_state)
     |> assign(:user_preferences, user_preferences)
     |> push_event("toggle_timestamps", %{
       show_timestamps: timestamp_state
     })}
  end

  @impl true
  def handle_event("toggle_mod_icons", %{"user" => _username}, socket) do
    mod_icon_state = Kernel.not(socket.assigns.show_mod_icons)

    {:ok, user_preferences} =
      Accounts.update_user_preference(socket.assigns.user_preferences, %{
        show_mod_icons: mod_icon_state
      })

    {:noreply,
     socket
     |> assign(:show_mod_icons, mod_icon_state)
     |> assign(:user_preferences, user_preferences)
     |> push_event("toggle_mod_icons", %{
       show_mod_icons: mod_icon_state
     })}
  end

  @impl true
  def handle_info({:chat_message, message}, socket) do
    {:noreply,
     socket
     |> assign(:update_action, "append")
     |> push_event("new_chat_message", %{
       message_id: message.id
     })
     |> update(:chat_messages, fn messages -> [message | messages] end)}
  end

  @impl true
  def handle_info({:user_timedout, bad_user}, socket) do
    {:noreply, push_event(socket, "remove_timed_out_user_messages", %{bad_user_id: bad_user.id})}
  end

  @impl true
  def handle_info({:message_deleted, message_id}, socket) do
    {:noreply, push_event(socket, "remove_deleted_message", %{message_id: message_id})}
  end

  defp list_chat_messages(%Channel{show_recent_chat_messages_only: true} = channel) do
    Chat.list_recent_chat_messages(channel)
  end

  defp list_chat_messages(channel) do
    Chat.list_chat_messages(channel)
  end

  defp background_style(channel) do
    url = Glimesh.ChatBackground.url({channel.chat_bg, channel}, :original)

    "--chat-bg-image: url('#{url}');"
  end
end
