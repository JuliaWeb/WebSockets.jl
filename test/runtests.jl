using WebSockets
using Base.Test

#is_control_frame is one line, checking one bit.
#get_websocket_key grabs a header.
#is_websocket_handshake grabs a header.

#generate_websocket_key makes a call to a library.
@test WebSockets.generate_websocket_key("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
