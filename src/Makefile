#
# makefile for the C programs for the DXSpider node
#

CFLAGS = -g -O

CLIENTOBJ = client.o sel.o cmsg.o chain.o debug.o
CLIENTBIN = client

$(CLIENTBIN) : $(CLIENTOBJ)
	$(CC) $(CFLAGS) $(CLIENTOBJ) -o $(CLIENTBIN) 

clean:
	rm -f $(CLIENTOBJ) $(CLIENTBIN) *~