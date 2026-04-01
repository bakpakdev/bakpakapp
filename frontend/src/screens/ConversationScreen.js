import React, { useState, useEffect, useRef } from 'react';
import {
  View,
  Text,
  FlatList,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { useRoute } from '@react-navigation/native';
import { api } from '../services/api';
import { AuthContext } from '../context/AuthContext';
import { SOCKET_URL } from '../config';
import io from 'socket.io-client';

export default function ConversationScreen() {
  const route = useRoute();
  const { conversationId, otherUserId } = route.params || {};
  const { user } = React.useContext(AuthContext);
  const [messages, setMessages] = useState([]);
  const [newMessage, setNewMessage] = useState('');
  const [loading, setLoading] = useState(true);
  const flatListRef = useRef(null);
  const socketRef = useRef(null);

  const loadMessages = async (convId = conversationId) => {
    if (!convId) return;
    try {
      const response = await api.get(`/messages/${convId}`);
      setMessages(response.data);
    } catch (error) {
      console.error('Error loading messages:', error);
    } finally {
      setLoading(false);
    }
  };

  const createOrGetConversation = async () => {
    if (!otherUserId) return;
    try {
      const response = await api.get(`/messages/conversations/${otherUserId}`);
      if (response.data?.id) {
        loadMessages(response.data.id);
      }
    } catch (error) {
      console.error('Error creating conversation:', error);
      setLoading(false);
    }
  };

  useEffect(() => {
    // Initialize socket only when component mounts
    let socket = null;
    try {
      socket = io(SOCKET_URL, {
        transports: ['websocket', 'polling'],
        reconnection: true,
        reconnectionAttempts: 5,
        reconnectionDelay: 1000,
      });
      socketRef.current = socket;

      socket.on('connect', () => {
        console.log('Socket connected');
      });

      socket.on('connect_error', (error) => {
        console.log('Socket connection error:', error);
      });

      if (conversationId) {
        loadMessages();
        socket.emit('join-conversation', conversationId);
      } else if (otherUserId) {
        createOrGetConversation();
      }

      socket.on('receive-message', (data) => {
        if (data.conversationId === conversationId) {
          setMessages((prev) => [...prev, data]);
        }
      });
    } catch (error) {
      console.error('Socket initialization error:', error);
      setLoading(false);
    }

    return () => {
      if (socket && conversationId) {
        socket.emit('leave-conversation', conversationId);
      }
      if (socket) {
        socket.disconnect();
      }
    };
  }, [conversationId, otherUserId]);

  const sendMessage = async () => {
    if (!newMessage.trim() || !conversationId) return;

    try {
      const response = await api.post('/messages', {
        conversationId,
        content: newMessage,
      });
      setMessages((prev) => [...prev, response.data]);
      setNewMessage('');
      if (socketRef.current && socketRef.current.connected) {
        socketRef.current.emit('send-message', {
          conversationId,
          message: response.data,
        });
      }
    } catch (error) {
      console.error('Error sending message:', error);
    }
  };

  const renderMessage = ({ item }) => {
    const isMyMessage = item.sender?.id === user?.id;

    return (
      <View
        style={[
          styles.messageContainer,
          isMyMessage ? styles.myMessage : styles.otherMessage,
        ]}
      >
        <Text style={[styles.messageText, isMyMessage && styles.myMessageText]}>
          {item.content}
        </Text>
        <Text style={[styles.messageTime, isMyMessage && styles.myMessageTime]}>
          {new Date(item.createdAt).toLocaleTimeString([], {
            hour: '2-digit',
            minute: '2-digit',
          })}
        </Text>
      </View>
    );
  };

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      style={styles.container}
    >
      <FlatList
        ref={flatListRef}
        data={messages}
        renderItem={renderMessage}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.messagesList}
        onContentSizeChange={() => flatListRef.current?.scrollToEnd()}
      />
      <View style={styles.inputContainer}>
        <TextInput
          style={styles.input}
          value={newMessage}
          onChangeText={setNewMessage}
          placeholder="Type a message..."
          multiline
        />
        <TouchableOpacity style={styles.sendButton} onPress={sendMessage}>
          <Text style={styles.sendButtonText}>Send</Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    paddingTop: 50,
  },
  messagesList: {
    padding: 15,
  },
  messageContainer: {
    maxWidth: '75%',
    padding: 12,
    borderRadius: 16,
    marginBottom: 10,
  },
  myMessage: {
    alignSelf: 'flex-end',
    backgroundColor: '#154733',
  },
  otherMessage: {
    alignSelf: 'flex-start',
    backgroundColor: '#f0f0f0',
  },
  messageText: {
    fontSize: 16,
    marginBottom: 4,
    color: '#333',
  },
  myMessageText: {
    color: '#fff',
  },
  messageTime: {
    fontSize: 12,
    color: '#999',
  },
  myMessageTime: {
    color: 'rgba(255,255,255,0.7)',
  },
  inputContainer: {
    flexDirection: 'row',
    padding: 15,
    borderTopWidth: 1,
    borderTopColor: '#eee',
    alignItems: 'flex-end',
  },
  input: {
    flex: 1,
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 20,
    paddingHorizontal: 15,
    paddingVertical: 10,
    maxHeight: 100,
    marginRight: 10,
  },
  sendButton: {
    backgroundColor: '#154733',
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 20,
  },
  sendButtonText: {
    color: '#fff',
    fontWeight: '600',
  },
});

