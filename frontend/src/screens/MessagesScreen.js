import React, { useState, useEffect, useRef, useContext } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  FlatList,
  Image,
  ScrollView,
  Dimensions,
  Platform,
  Animated,
  KeyboardAvoidingView,
} from 'react-native';
import { useNavigation, useRoute } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { api } from '../services/api';
import { AuthContext } from '../context/AuthContext';

const { width } = Dimensions.get('window');
const isTablet = width >= 768;

export default function MessagesScreen() {
  const [selectedChatId, setSelectedChatId] = useState(null);
  const [activeTab, setActiveTab] = useState('buying');
  const [searchTerm, setSearchTerm] = useState('');
  const [inputValue, setInputValue] = useState('');
  const [chats, setChats] = useState([]);
  const [messages, setMessages] = useState([]);
  const [loading, setLoading] = useState(false);
  const [loadingMessages, setLoadingMessages] = useState(false);
  const messagesEndRef = useRef(null);
  const scrollViewRef = useRef(null);
  const navigation = useNavigation();
  const route = useRoute();
  const { user } = useContext(AuthContext);

  const selectedChat = chats.find((c) => c.id === selectedChatId);

  useEffect(() => {
    loadConversations();
  }, []);

  // If navigated here with an otherUserId (e.g. from ProductDetail),
  // create/get the conversation and focus it.
  useEffect(() => {
    const otherUserId = route.params?.otherUserId;
    if (!otherUserId || !user) return;

    const openConversationForUser = async () => {
      try {
        // This will create the conversation if it doesn't exist
        const response = await api.get(`/messages/conversations/${otherUserId}`);
        const conv = response.data;
        if (conv?.id) {
          // Refresh the conversations list so it contains this convo
          await loadConversations();
          setSelectedChatId(conv.id);
        }
      } catch (error) {
        console.error('Error opening conversation from route params:', error);
      }
    };

    openConversationForUser();
  }, [route, user]);

  useEffect(() => {
    if (!selectedChatId || !user) return;

    const loadMessages = async () => {
      try {
        setLoadingMessages(true);
        const response = await api.get(`/messages/${selectedChatId}`);
        const msgs = (response.data || []).map((m) => ({
          id: m.id,
          senderId: m.senderId === user.id ? 'me' : m.senderId,
          text: m.content,
          timestamp: new Date(m.createdAt).toLocaleTimeString([], {
            hour: 'numeric',
            minute: '2-digit',
          }),
          isRead: m.isRead,
        }));
        setMessages(msgs);
        setTimeout(() => {
          scrollViewRef.current?.scrollToEnd({ animated: true });
        }, 100);
      } catch (error) {
        console.error('Error loading messages:', error);
      } finally {
        setLoadingMessages(false);
      }
    };

    loadMessages();
  }, [selectedChatId, user]);

  const loadConversations = async () => {
    try {
      setLoading(true);
      const response = await api.get('/messages/conversations');
      const data = response.data || [];

      const transformed = data.map((conv) => {
        const otherUser =
          (conv.participants || []).find((p) => p.id !== user?.id) ||
          (conv.participants || [])[0] ||
          {};
        const lastMessage = (conv.messages || [])[0];

        return {
          id: conv.id,
          participant: {
            id: otherUser.id,
            name: otherUser.username || 'Unknown',
            avatar: otherUser.avatar || 'https://via.placeholder.com/100',
            isOnline: false,
            rating: 5.0,
            college: '',
          },
          item: {
            id: '',
            name: 'Item',
            price: 0,
            image: '',
            status: 'available',
          },
          lastMessage: lastMessage ? lastMessage.content : '',
          lastTimestamp: lastMessage
            ? new Date(lastMessage.createdAt).toLocaleTimeString([], {
                hour: 'numeric',
                minute: '2-digit',
              })
            : '',
          unreadCount: 0,
        };
      });

      setChats(transformed);
    } catch (error) {
      console.error('Error loading conversations:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSendMessage = () => {
    if (!inputValue.trim() || !selectedChatId) return;
    // TODO: hook up to backend /api/messages
    setInputValue('');
  };

  const filteredChats = chats.filter(
    (chat) =>
      chat.participant.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      chat.item.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const quickActions = [
    'Is this still available?',
    'Can you meet today?',
    "What's your best price?",
  ];

  const renderChatItem = ({ item }) => {
    const isSelected = selectedChatId === item.id;
    return (
      <TouchableOpacity
        style={[styles.chatItem, isSelected && styles.chatItemSelected]}
        onPress={() => setSelectedChatId(item.id)}
        activeOpacity={0.7}
      >
        <View style={styles.chatAvatarContainer}>
          <Image
            source={{ uri: item.participant.avatar }}
            style={styles.chatAvatar}
          />
          {item.participant.isOnline && (
            <View style={styles.onlineIndicator} />
          )}
        </View>
        <View style={styles.chatInfo}>
          <View style={styles.chatHeaderRow}>
            <Text style={styles.chatName} numberOfLines={1}>
              {item.participant.name}
            </Text>
            <Text style={styles.chatTimestamp}>{item.lastTimestamp}</Text>
          </View>
          <View style={styles.chatItemRow}>
            <Ionicons name="pricetag-outline" size={12} color="#94a3b8" />
            <Text style={styles.chatItemName} numberOfLines={1}>
              {item.item.name}
            </Text>
          </View>
          <Text
            style={[
              styles.chatLastMessage,
              item.unreadCount > 0 && styles.chatLastMessageUnread,
            ]}
            numberOfLines={1}
          >
            {item.lastMessage}
          </Text>
        </View>
        {item.unreadCount > 0 && (
          <View style={styles.unreadBadge}>
            <View style={styles.unreadDot} />
          </View>
        )}
      </TouchableOpacity>
    );
  };

  const renderMessage = (msg, index) => {
    const isMe = msg.senderId === 'me';
    return (
      <View
        key={msg.id || index}
        style={[
          styles.messageContainer,
          isMe ? styles.messageContainerRight : styles.messageContainerLeft,
        ]}
      >
        <View
          style={[
            styles.messageBubble,
            isMe ? styles.messageBubbleMe : styles.messageBubbleOther,
          ]}
        >
          <Text
            style={[
              styles.messageText,
              isMe ? styles.messageTextMe : styles.messageTextOther,
            ]}
          >
            {msg.text}
          </Text>
        </View>

        {msg.offerAmount && (
          <View style={styles.offerBubble}>
            <View style={styles.offerHeader}>
              <Text style={styles.offerLabel}>Custom Offer</Text>
              <Text style={styles.offerAmount}>${msg.offerAmount.toFixed(2)}</Text>
            </View>
            <View style={styles.offerActions}>
              <TouchableOpacity style={styles.offerButtonAccept}>
                <Text style={styles.offerButtonText}>Accept Offer</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.offerButtonDecline}>
                <Text style={[styles.offerButtonText, styles.offerButtonTextDecline]}>
                  Decline
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        )}

        {msg.offerStatus === 'accepted' && (
          <View style={styles.offerAcceptedBadge}>
            <Ionicons name="checkmark" size={14} color="#154733" />
            <Text style={styles.offerAcceptedText}>Offer Accepted</Text>
          </View>
        )}

        <View style={styles.messageMeta}>
          <Text style={styles.messageTimestamp}>{msg.timestamp}</Text>
          {isMe &&
            (msg.isRead ? (
              <Ionicons name="checkmark-done" size={12} color="#154733" />
            ) : (
              <Ionicons name="checkmark" size={12} color="#cbd5e1" />
            ))}
        </View>
      </View>
    );
  };

  // Show sidebar on tablet/desktop, or when no chat is selected on mobile
  const showSidebar = isTablet || !selectedChatId;
  // Show chat view on tablet/desktop always, or when chat is selected on mobile
  const showChatView = isTablet || selectedChatId;

  return (
    <View style={styles.container}>
      {/* Sidebar - Chat List */}
      {showSidebar && (
        <View style={[styles.sidebar, isTablet && styles.sidebarTablet]}>
          {/* Header */}
          <View style={styles.sidebarHeader}>
            <Text style={styles.sidebarTitle}>Messages</Text>

            {/* Tabs */}
            <View style={styles.tabContainer}>
              <TouchableOpacity
                style={[styles.tab, activeTab === 'buying' && styles.tabActive]}
                onPress={() => setActiveTab('buying')}
                activeOpacity={0.7}
              >
                <Text
                  style={[
                    styles.tabText,
                    activeTab === 'buying' && styles.tabTextActive,
                  ]}
                >
                  Buying
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.tab, activeTab === 'selling' && styles.tabActive]}
                onPress={() => setActiveTab('selling')}
                activeOpacity={0.7}
              >
                <Text
                  style={[
                    styles.tabText,
                    activeTab === 'selling' && styles.tabTextActive,
                  ]}
                >
                  Selling
                </Text>
              </TouchableOpacity>
            </View>

            {/* Search */}
            <View style={styles.searchContainer}>
              <Ionicons
                name="search-outline"
                size={16}
                color="#94a3b8"
                style={styles.searchIcon}
              />
              <TextInput
                style={styles.searchInput}
                placeholder="Search conversations..."
                placeholderTextColor="#94a3b8"
                value={searchTerm}
                onChangeText={setSearchTerm}
              />
            </View>
          </View>

          {/* Chat List */}
          <FlatList
            data={filteredChats}
            renderItem={renderChatItem}
            keyExtractor={(item) => item.id}
            style={styles.chatList}
            contentContainerStyle={styles.chatListContent}
          />
        </View>
      )}

      {/* Chat View */}
      {showChatView && (
        <View style={[styles.chatView, isTablet && styles.chatViewTablet]}>
          {selectedChat ? (
            <>
              {/* Active Chat Header */}
              <View style={styles.chatHeader}>
                <View style={styles.chatHeaderLeft}>
                  {!isTablet && (
                    <TouchableOpacity
                      onPress={() => setSelectedChatId(null)}
                      style={styles.backButton}
                    >
                      <Ionicons name="arrow-back" size={20} color="#0f172a" />
                    </TouchableOpacity>
                  )}
                  <Image
                    source={{ uri: selectedChat.participant.avatar }}
                    style={styles.chatHeaderAvatar}
                  />
                  <View style={styles.chatHeaderInfo}>
                    <View style={styles.chatHeaderNameRow}>
                      <Text style={styles.chatHeaderName}>
                        {selectedChat.participant.name}
                      </Text>
                      <Ionicons
                        name="shield-checkmark"
                        size={14}
                        color="#154733"
                      />
                    </View>
                    <Text style={styles.chatHeaderSubtext}>
                      {selectedChat.participant.rating} ★{' '}
                      {selectedChat.participant.college
                        ? `• ${selectedChat.participant.college}`
                        : ''}
                    </Text>
                  </View>
                </View>
                <View style={styles.chatHeaderActions}>
                  <TouchableOpacity style={styles.chatHeaderButton}>
                    <Ionicons name="flag-outline" size={16} color="#64748b" />
                  </TouchableOpacity>
                  <TouchableOpacity style={styles.chatHeaderButton}>
                    <Ionicons name="trash-outline" size={16} color="#64748b" />
                  </TouchableOpacity>
                  <TouchableOpacity style={styles.chatHeaderButton}>
                    <Ionicons
                      name="ellipsis-vertical"
                      size={20}
                      color="#64748b"
                    />
                  </TouchableOpacity>
                </View>
              </View>

              {/* Item Mini Card */}
              <TouchableOpacity
                style={styles.itemCard}
                onPress={() =>
                  navigation.navigate('ProductDetail', {
                    productId: selectedChat.item.id,
                  })
                }
                activeOpacity={0.7}
              >
                <Image
                  source={{ uri: selectedChat.item.image }}
                  style={styles.itemCardImage}
                />
                <View style={styles.itemCardInfo}>
                  <Text style={styles.itemCardName} numberOfLines={1}>
                    {selectedChat.item.name}
                  </Text>
                  <Text style={styles.itemCardPrice}>
                    ${selectedChat.item.price.toFixed(2)}
                  </Text>
                </View>
                <View style={styles.itemCardActions}>
                  <TouchableOpacity
                    style={styles.itemCardButton}
                    onPress={() =>
                      navigation.navigate('ProductDetail', {
                        productId: selectedChat.item.id,
                      })
                    }
                  >
                    <Text style={styles.itemCardButtonText}>View Item</Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={[styles.itemCardButton, styles.itemCardButtonPrimary]}
                    onPress={() =>
                      navigation.navigate('ProductDetail', {
                        productId: selectedChat.item.id,
                      })
                    }
                  >
                    <Ionicons name="cart-outline" size={12} color="#fff" />
                    <Text
                      style={[
                        styles.itemCardButtonText,
                        styles.itemCardButtonTextPrimary,
                      ]}
                    >
                      Buy Now
                    </Text>
                  </TouchableOpacity>
                </View>
              </TouchableOpacity>

              {/* Messages Area */}
              <KeyboardAvoidingView
                style={styles.messagesContainer}
                behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
                keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 0}
              >
                <ScrollView
                  ref={scrollViewRef}
                  style={styles.messagesScroll}
                  contentContainerStyle={styles.messagesContent}
                  onContentSizeChange={() => {
                    scrollViewRef.current?.scrollToEnd({ animated: true });
                  }}
                >
                  {/* Safety Notice */}
                  <View style={styles.safetyNotice}>
                    <View style={styles.safetyBadge}>
                      <Text style={styles.safetyBadgeText}>Safety First</Text>
                    </View>
                    <Text style={styles.safetyText}>
                      Meet in public places and never share your phone number or
                      bank details.
                    </Text>
                  </View>

                  {/* Messages */}
                  {loadingMessages ? (
                    <Text style={styles.messageTimestamp}>Loading...</Text>
                  ) : (
                    messages.map((msg, idx) => renderMessage(msg, idx))
                  )}
                  <View ref={messagesEndRef} style={{ height: 20 }} />
                </ScrollView>

                {/* Quick Actions */}
                <ScrollView
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  style={styles.quickActions}
                  contentContainerStyle={styles.quickActionsContent}
                >
                  {quickActions.map((action, idx) => (
                    <TouchableOpacity
                      key={idx}
                      style={styles.quickActionButton}
                      onPress={() => setInputValue(action)}
                      activeOpacity={0.7}
                    >
                      <Text style={styles.quickActionText}>{action}</Text>
                    </TouchableOpacity>
                  ))}
                </ScrollView>

                {/* Input Bar */}
                <View style={styles.inputContainer}>
                  <View style={styles.inputWrapper}>
                    <TouchableOpacity style={styles.inputIconButton}>
                      <Ionicons name="image-outline" size={20} color="#64748b" />
                    </TouchableOpacity>
                    <TextInput
                      style={styles.input}
                      placeholder="Type a message..."
                      placeholderTextColor="#94a3b8"
                      value={inputValue}
                      onChangeText={setInputValue}
                      multiline
                      maxLength={500}
                    />
                    <TouchableOpacity
                      onPress={handleSendMessage}
                      disabled={!inputValue.trim()}
                      style={[
                        styles.sendButton,
                        !inputValue.trim() && styles.sendButtonDisabled,
                      ]}
                    >
                      <Ionicons
                        name="send"
                        size={20}
                        color={inputValue.trim() ? '#fff' : '#cbd5e1'}
                      />
                    </TouchableOpacity>
                  </View>
                </View>
              </KeyboardAvoidingView>
            </>
          ) : (
            <View style={styles.emptyChatView}>
              <View style={styles.emptyChatIcon}>
                <Ionicons name="chatbubbles-outline" size={32} color="#cbd5e1" />
              </View>
              <Text style={styles.emptyChatTitle}>Your Messages</Text>
              <Text style={styles.emptyChatText}>
                Send an offer or ask a question about an item to start a
                conversation.
              </Text>
              <View style={styles.emptyChatStats}>
                <View style={styles.emptyChatStat}>
                  <Ionicons name="time-outline" size={20} color="#94a3b8" />
                  <Text style={styles.emptyChatStatLabel}>Pending Offers</Text>
                  <Text style={styles.emptyChatStatValue}>2</Text>
                </View>
                <View style={styles.emptyChatStat}>
                  <Ionicons name="cart-outline" size={20} color="#94a3b8" />
                  <Text style={styles.emptyChatStatLabel}>Items Sold</Text>
                  <Text style={styles.emptyChatStatValue}>14</Text>
                </View>
              </View>
            </View>
          )}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    flexDirection: 'row',
    backgroundColor: '#ffffff',
  },
  sidebar: {
    width: '100%',
    flex: 1,
    backgroundColor: '#ffffff',
    borderRightWidth: 1,
    borderRightColor: '#f1f5f9',
  },
  sidebarTablet: {
    width: 384,
    maxWidth: 384,
  },
  sidebarHeader: {
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#f8fafc',
    paddingTop: 50,
  },
  sidebarTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#0f172a',
    marginBottom: 16,
    letterSpacing: -0.5,
  },
  tabContainer: {
    flexDirection: 'row',
    backgroundColor: '#f1f5f9',
    borderRadius: 8,
    padding: 2,
    marginBottom: 16,
  },
  tab: {
    flex: 1,
    paddingVertical: 6,
    alignItems: 'center',
    borderRadius: 6,
  },
  tabActive: {
    backgroundColor: '#e6f2ed',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  tabText: {
    fontSize: 14,
    fontWeight: '500',
    color: '#64748b',
  },
  tabTextActive: {
    color: '#154733',
    fontWeight: '700',
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#f1f5f9',
    borderRadius: 20,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  searchIcon: {
    marginRight: 8,
  },
  searchInput: {
    flex: 1,
    fontSize: 14,
    color: '#0f172a',
    padding: 0,
  },
  chatList: {
    flex: 1,
  },
  chatListContent: {
    paddingBottom: 16,
  },
  chatItem: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#f8fafc',
    backgroundColor: '#ffffff',
  },
  chatItemSelected: {
    backgroundColor: '#f8fafc',
  },
  chatAvatarContainer: {
    position: 'relative',
    marginRight: 12,
  },
  chatAvatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
  },
  onlineIndicator: {
    position: 'absolute',
    bottom: 0,
    right: 0,
    width: 14,
    height: 14,
    borderRadius: 7,
    backgroundColor: '#154733',
    borderWidth: 2,
    borderColor: '#ffffff',
  },
  chatInfo: {
    flex: 1,
    minWidth: 0,
  },
  chatHeaderRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 2,
  },
  chatName: {
    fontSize: 14,
    fontWeight: '600',
    color: '#0f172a',
    flex: 1,
  },
  chatTimestamp: {
    fontSize: 10,
    fontWeight: 'bold',
    color: '#94a3b8',
    textTransform: 'uppercase',
    marginLeft: 8,
  },
  chatItemRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 4,
    gap: 6,
  },
  chatItemName: {
    fontSize: 12,
    color: '#64748b',
    flex: 1,
  },
  chatLastMessage: {
    fontSize: 12,
    color: '#64748b',
  },
  chatLastMessageUnread: {
    color: '#000000',
    fontWeight: '600',
  },
  unreadBadge: {
    marginLeft: 8,
    justifyContent: 'center',
    alignItems: 'center',
  },
  unreadDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: '#154733',
  },
  chatView: {
    flex: 1,
    backgroundColor: '#ffffff',
  },
  chatViewTablet: {
    borderLeftWidth: 1,
    borderLeftColor: '#f1f5f9',
  },
  chatHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#f1f5f9',
    paddingTop: 50,
  },
  chatHeaderLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    gap: 12,
  },
  backButton: {
    padding: 8,
    marginRight: -8,
  },
  chatHeaderAvatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
  },
  chatHeaderInfo: {
    flex: 1,
  },
  chatHeaderNameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    marginBottom: 2,
  },
  chatHeaderName: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#0f172a',
  },
  chatHeaderSubtext: {
    fontSize: 11,
    color: '#64748b',
  },
  chatHeaderActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  chatHeaderButton: {
    padding: 8,
  },
  itemCard: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 10,
    backgroundColor: '#f8fafc',
    borderBottomWidth: 1,
    borderBottomColor: '#f1f5f9',
  },
  itemCardImage: {
    width: 48,
    height: 48,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#f1f5f9',
    marginRight: 12,
  },
  itemCardInfo: {
    flex: 1,
    marginRight: 12,
  },
  itemCardName: {
    fontSize: 12,
    fontWeight: 'bold',
    color: '#0f172a',
    marginBottom: 2,
  },
  itemCardPrice: {
    fontSize: 12,
    fontWeight: '500',
    color: '#475569',
  },
  itemCardActions: {
    flexDirection: 'row',
    gap: 8,
  },
  itemCardButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#e2e8f0',
  },
  itemCardButtonPrimary: {
    backgroundColor: '#154733',
    borderColor: '#000000',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  itemCardButtonText: {
    fontSize: 12,
    fontWeight: 'bold',
    color: '#0f172a',
  },
  itemCardButtonTextPrimary: {
    color: '#ffffff',
  },
  messagesContainer: {
    flex: 1,
  },
  messagesScroll: {
    flex: 1,
  },
  messagesContent: {
    padding: 16,
    paddingBottom: 8,
  },
  safetyNotice: {
    alignItems: 'center',
    paddingVertical: 24,
    marginBottom: 16,
  },
  safetyBadge: {
    paddingHorizontal: 12,
    paddingVertical: 4,
    backgroundColor: '#f1f5f9',
    borderRadius: 20,
    marginBottom: 8,
  },
  safetyBadgeText: {
    fontSize: 10,
    fontWeight: 'bold',
    color: '#64748b',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  safetyText: {
    fontSize: 12,
    color: '#94a3b8',
    textAlign: 'center',
    maxWidth: 300,
    lineHeight: 18,
  },
  messageContainer: {
    marginBottom: 16,
  },
  messageContainerLeft: {
    alignItems: 'flex-start',
  },
  messageContainerRight: {
    alignItems: 'flex-end',
  },
  messageBubble: {
    maxWidth: '80%',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 16,
  },
  messageBubbleMe: {
    backgroundColor: '#154733',
    borderTopRightRadius: 4,
  },
  messageBubbleOther: {
    backgroundColor: '#f1f5f9',
    borderTopLeftRadius: 4,
  },
  messageText: {
    fontSize: 14,
  },
  messageTextMe: {
    color: '#ffffff',
  },
  messageTextOther: {
    color: '#0f172a',
  },
  offerBubble: {
    marginTop: 8,
    maxWidth: 300,
    borderWidth: 1,
    borderColor: '#f1f5f9',
    borderRadius: 12,
    backgroundColor: '#ffffff',
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  offerHeader: {
    padding: 12,
    backgroundColor: '#f8fafc',
    borderBottomWidth: 1,
    borderBottomColor: '#f1f5f9',
  },
  offerLabel: {
    fontSize: 10,
    fontWeight: 'bold',
    color: '#94a3b8',
    textTransform: 'uppercase',
    marginBottom: 4,
  },
  offerAmount: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#0f172a',
  },
  offerActions: {
    flexDirection: 'row',
    padding: 8,
    gap: 8,
  },
  offerButtonAccept: {
    flex: 1,
    paddingVertical: 6,
    borderRadius: 8,
    backgroundColor: '#154733',
    alignItems: 'center',
  },
  offerButtonDecline: {
    flex: 1,
    paddingVertical: 6,
    borderRadius: 8,
    backgroundColor: '#f1f5f9',
    alignItems: 'center',
  },
  offerButtonText: {
    fontSize: 12,
    fontWeight: 'bold',
    color: '#ffffff',
  },
  offerButtonTextDecline: {
    color: '#475569',
  },
  offerAcceptedBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 4,
    paddingHorizontal: 12,
    paddingVertical: 6,
    backgroundColor: '#dcfce7',
    borderRadius: 20,
    borderWidth: 1,
    borderColor: '#bbf7d0',
    gap: 6,
    alignSelf: 'flex-start',
  },
  offerAcceptedText: {
    fontSize: 10,
    fontWeight: 'bold',
    color: '#154733',
    textTransform: 'uppercase',
  },
  messageMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 4,
    paddingHorizontal: 4,
    gap: 6,
  },
  messageTimestamp: {
    fontSize: 10,
    color: '#94a3b8',
    fontWeight: '500',
  },
  quickActions: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderTopWidth: 1,
    borderTopColor: '#f1f5f9',
  },
  quickActionsContent: {
    gap: 8,
  },
  quickActionButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    backgroundColor: '#f1f5f9',
    borderRadius: 20,
  },
  quickActionText: {
    fontSize: 12,
    fontWeight: '600',
    color: '#475569',
  },
  inputContainer: {
    padding: 16,
    borderTopWidth: 1,
    borderTopColor: '#f1f5f9',
    backgroundColor: '#ffffff',
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#f8fafc',
    borderWidth: 1,
    borderColor: '#e2e8f0',
    borderRadius: 16,
    padding: 8,
    gap: 8,
  },
  inputIconButton: {
    padding: 8,
  },
  input: {
    flex: 1,
    fontSize: 14,
    color: '#0f172a',
    padding: 0,
    maxHeight: 100,
  },
  sendButton: {
    padding: 8,
    borderRadius: 12,
    backgroundColor: '#154733',
  },
  sendButtonDisabled: {
    backgroundColor: '#f1f5f9',
  },
  emptyChatView: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
  },
  emptyChatIcon: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: '#f8fafc',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 24,
  },
  emptyChatTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#0f172a',
    marginBottom: 8,
  },
  emptyChatText: {
    fontSize: 14,
    color: '#64748b',
    textAlign: 'center',
    maxWidth: 300,
    marginBottom: 32,
    lineHeight: 20,
  },
  emptyChatStats: {
    flexDirection: 'row',
    gap: 16,
    width: '100%',
    maxWidth: 300,
  },
  emptyChatStat: {
    flex: 1,
    padding: 16,
    borderWidth: 1,
    borderColor: '#f1f5f9',
    borderRadius: 16,
    backgroundColor: '#f8fafc',
    alignItems: 'center',
  },
  emptyChatStatLabel: {
    fontSize: 12,
    fontWeight: 'bold',
    color: '#475569',
    marginTop: 8,
    marginBottom: 4,
  },
  emptyChatStatValue: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#0f172a',
  },
});
