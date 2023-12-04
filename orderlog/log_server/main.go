package main

import (
	"context"
	"database/sql"
    _ "github.com/lib/pq"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"os"

	pb "github.com/hamza-boudouche/orderlog/log"
	"google.golang.org/grpc"
)

var (
	port = flag.Int("port", 50051, "The server port")
    dbUser = "log"
    dbPassword = os.Getenv("POSTGRES_PASSWORD")
    dbHost = os.Getenv("CLUSTER_EXAMPLE_2_RW_SERVICE_HOST")
    dbPort = os.Getenv("CLUSTER_EXAMPLE_2_RW_PORT_5432_TCP_PORT")
    dbName = "postgres"
    connStr = fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=disable", dbUser, dbPassword, dbHost, dbPort, dbName)
    db *sql.DB
)

func init() {
    // connection to default postgres db
    var err error
    db, err = sql.Open("postgres", connStr)
    if err != nil {
        fmt.Println("failed to connect to db")
        log.Fatal(err)
    }
    fmt.Println("connected to db")
    // creating log database
    dbName = "log"
    _, err = db.Query("create database " + dbName)
    // connecting to log database
    connStr = fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=disable", dbUser, dbPassword, dbHost, dbPort, dbName)
    db, err = sql.Open("postgres", connStr)
    fmt.Println("here")
    if err != nil {
        fmt.Println("failed to connect to new db")
        log.Fatal(err)
    }
    fmt.Println("here")
    // creating logs table if it doesn't exist
    _, err = db.Exec("create table if not exists logs ( id serial primary key, contents varchar (1000) )");
    if err != nil {
        log.Fatal(err)
    }
}

func writeLog(db *sql.DB, contents string) error {
    _, err := db.Exec("insert into logs(contents) values($1)", contents)
    return err
}

type server struct {
    pb.UnimplementedLoggerServer
}

// SayHello implements helloworld.GreeterServer
func (s *server) Log(ctx context.Context, in *pb.Entry) (*pb.Reply, error) {
	log.Printf("Received: %v", in.GetContent())
    // writing to db
    err := writeLog(db, in.GetContent())
    if err != nil {
        return &pb.Reply{Ok: false}, errors.New("failed to write log into db")
    }
    return &pb.Reply{Ok: true}, nil
}

func main() {
	flag.Parse()
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	s := grpc.NewServer()
	pb.RegisterLoggerServer(s, &server{})
	log.Printf("server listening at %v", lis.Addr())
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
