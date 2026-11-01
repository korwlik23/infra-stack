// ตัวอย่าง Go service ที่ทำตามข้อตกลงของ templates/go (docs/29-deploy-go.md)
//
//	server          ฟัง :8080 — GET /healthz (ping DB) · GET / (นับข้อมูล seed)
//	server migrate  รัน migrations/*.sql ที่ยังไม่เคยรัน (จำใน schema_migrations)
//	server seed     รัน seeds/*.sql — ต้องรันซ้ำได้ (ON CONFLICT DO NOTHING)
//
// ไฟล์ SQL ถูก embed ใน binary — image สุดท้ายมีแค่ binary + seeds/ (ไว้ให้ deploy จับว่า seed เปลี่ยน)
package main

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"strings"
	"syscall"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

//go:embed migrations/*.sql
var migrations embed.FS

//go:embed seeds/*.sql
var seeds embed.FS

func main() {
	db, err := sql.Open("pgx", os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer db.Close()

	cmd := "serve"
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}
	ctx := context.Background()
	switch cmd {
	case "serve":
		err = serve(db)
	case "migrate":
		err = migrate(ctx, db)
	case "seed":
		err = runFiles(ctx, db, seeds, "seeds")
	default:
		err = fmt.Errorf("unknown command %q (serve | migrate | seed)", cmd)
	}
	if err != nil {
		log.Fatal(err)
	}
}

func serve(db *sql.DB) error {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := db.PingContext(ctx); err != nil {
			http.Error(w, "db down", http.StatusServiceUnavailable)
			return
		}
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		var n int
		if err := db.QueryRowContext(r.Context(), "SELECT count(*) FROM roles").Scan(&n); err != nil {
			http.Error(w, "query failed", http.StatusInternalServerError)
			return
		}
		fmt.Fprintf(w, "hello from go-app — %d roles\n", n)
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	srv := &http.Server{Addr: ":" + port, Handler: mux, ReadHeaderTimeout: 10 * time.Second}

	// SIGTERM จาก docker stop → ปิดรับ connection ใหม่ แล้วรอ request ที่ค้างจบ
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		<-stop
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	}()

	log.Printf("listening on :%s", port)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func migrate(ctx context.Context, db *sql.DB) error {
	if _, err := db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}
	names, err := sqlFiles(migrations, "migrations")
	if err != nil {
		return err
	}
	for _, name := range names {
		var done bool
		if err := db.QueryRowContext(ctx, "SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE name = $1)", name).Scan(&done); err != nil {
			return err
		}
		if done {
			continue
		}
		body, err := migrations.ReadFile("migrations/" + name)
		if err != nil {
			return err
		}
		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, string(body)); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("migration %s: %w", name, err)
		}
		if _, err := tx.ExecContext(ctx, "INSERT INTO schema_migrations (name) VALUES ($1)", name); err != nil {
			_ = tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
		log.Printf("migrated %s", name)
	}
	log.Print("migrate: up to date")
	return nil
}

func runFiles(ctx context.Context, db *sql.DB, fsys embed.FS, dir string) error {
	names, err := sqlFiles(fsys, dir)
	if err != nil {
		return err
	}
	for _, name := range names {
		body, err := fsys.ReadFile(dir + "/" + name)
		if err != nil {
			return err
		}
		if _, err := db.ExecContext(ctx, string(body)); err != nil {
			return fmt.Errorf("%s %s: %w", dir, name, err)
		}
		log.Printf("%s: ran %s", dir, name)
	}
	return nil
}

func sqlFiles(fsys embed.FS, dir string) ([]string, error) {
	entries, err := fs.ReadDir(fsys, dir)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names, nil
}
