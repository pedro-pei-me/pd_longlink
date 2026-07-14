const http = require('http');

const server = http.createServer((req, res) => {
  if (req.url === '/sse') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Accept, Last-Event-ID',
    });

    console.log('SSE connection established');
    console.log('Last-Event-ID:', req.headers['last-event-id'] || 'none');

    let count = 0;
    const interval = setInterval(() => {
      count++;
      
      const event = `event: message
id: ${Date.now()}
data: {"id": ${count}, "timestamp": "${new Date().toISOString()}", "message": "Hello from SSE server! Count: ${count}"}

`;
      res.write(event);
      console.log(`Sent message ${count}`);
    }, 2000);

    req.on('close', () => {
      clearInterval(interval);
      console.log('SSE connection closed');
    });
  } else if (req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('SSE Test Server\nUse /sse endpoint for SSE stream');
  } else {
    res.writeHead(404);
    res.end();
  }
});

const PORT = 3000;
server.listen(PORT, () => {
  console.log(`SSE Test Server running on http://localhost:${PORT}`);
  console.log(`SSE endpoint: http://localhost:${PORT}/sse`);
});
