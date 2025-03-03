--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4 (Ubuntu 17.4-1.pgdg24.04+2)
-- Dumped by pg_dump version 17.4 (Ubuntu 17.4-1.pgdg24.04+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: cifrar_contraseña(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public."cifrar_contraseña"(password text) RETURNS bytea
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN crypt(password, gen_salt('bf'));
END;
$$;


ALTER FUNCTION public."cifrar_contraseña"(password text) OWNER TO postgres;

--
-- Name: registrar_auditoria_ventas(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.registrar_auditoria_ventas() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO auditoria_ventas(usuario_id, venta_id, accion, fecha, estado_nuevo)
        VALUES (NULL, NEW.id, 'insert', NOW(), row_to_json(NEW));
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO auditoria_ventas(usuario_id, venta_id, accion, fecha, estado_anterior, estado_nuevo)
        VALUES (NULL, NEW.id, 'update', NOW(), row_to_json(OLD), row_to_json(NEW));
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO auditoria_ventas(usuario_id, venta_id, accion, fecha, estado_anterior)
        VALUES (NULL, OLD.id, 'delete', NOW(), row_to_json(OLD));
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.registrar_auditoria_ventas() OWNER TO postgres;

--
-- Name: verificar_contraseña(text, bytea); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public."verificar_contraseña"(password text, hash bytea) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN crypt(password, hash) = hash;
END;
$$;


ALTER FUNCTION public."verificar_contraseña"(password text, hash bytea) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auditoria_ventas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auditoria_ventas (
    id integer NOT NULL,
    usuario_id integer,
    venta_id integer,
    accion character varying(10) NOT NULL,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    estado_anterior jsonb,
    estado_nuevo jsonb,
    CONSTRAINT auditoria_ventas_accion_check CHECK (((accion)::text = ANY ((ARRAY['insert'::character varying, 'update'::character varying, 'delete'::character varying])::text[])))
);


ALTER TABLE public.auditoria_ventas OWNER TO postgres;

--
-- Name: TABLE auditoria_ventas; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.auditoria_ventas IS 'Registra cambios en las ventas con detalles de auditoría.';


--
-- Name: auditoria_ventas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.auditoria_ventas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.auditoria_ventas_id_seq OWNER TO postgres;

--
-- Name: auditoria_ventas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.auditoria_ventas_id_seq OWNED BY public.auditoria_ventas.id;


--
-- Name: categorias; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.categorias (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    descripcion text
);


ALTER TABLE public.categorias OWNER TO postgres;

--
-- Name: TABLE categorias; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.categorias IS 'Almacena las categorías de productos.';


--
-- Name: categorias_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.categorias_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categorias_id_seq OWNER TO postgres;

--
-- Name: categorias_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.categorias_id_seq OWNED BY public.categorias.id;


--
-- Name: clientes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.clientes (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    email character varying(100),
    telefono character varying(20),
    direccion text,
    CONSTRAINT clientes_email_check CHECK (((email)::text ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'::text))
);


ALTER TABLE public.clientes OWNER TO postgres;

--
-- Name: TABLE clientes; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.clientes IS 'Almacena la información de los clientes.';


--
-- Name: clientes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.clientes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clientes_id_seq OWNER TO postgres;

--
-- Name: clientes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.clientes_id_seq OWNED BY public.clientes.id;


--
-- Name: detalle_ventas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.detalle_ventas (
    id integer NOT NULL,
    venta_id integer,
    producto_id integer,
    cantidad integer NOT NULL,
    precio_unitario numeric(10,2) NOT NULL,
    CONSTRAINT detalle_ventas_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT detalle_ventas_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric))
);


ALTER TABLE public.detalle_ventas OWNER TO postgres;

--
-- Name: TABLE detalle_ventas; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.detalle_ventas IS 'Registra el detalle de cada venta con los productos vendidos.';


--
-- Name: detalle_ventas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.detalle_ventas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.detalle_ventas_id_seq OWNER TO postgres;

--
-- Name: detalle_ventas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.detalle_ventas_id_seq OWNED BY public.detalle_ventas.id;


--
-- Name: historial_stock; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.historial_stock (
    id integer NOT NULL,
    producto_id integer,
    usuario_id integer,
    cantidad integer NOT NULL,
    tipo_movimiento character varying(10) NOT NULL,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT historial_stock_tipo_movimiento_check CHECK (((tipo_movimiento)::text = ANY ((ARRAY['entrada'::character varying, 'salida'::character varying])::text[])))
);


ALTER TABLE public.historial_stock OWNER TO postgres;

--
-- Name: TABLE historial_stock; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.historial_stock IS 'Registra cambios en el stock de los productos con tipo de movimiento y usuario responsable.';


--
-- Name: historial_stock_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.historial_stock_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.historial_stock_id_seq OWNER TO postgres;

--
-- Name: historial_stock_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.historial_stock_id_seq OWNED BY public.historial_stock.id;


--
-- Name: log_errores; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.log_errores (
    id integer NOT NULL,
    usuario_id integer,
    error_mensaje text NOT NULL,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.log_errores OWNER TO postgres;

--
-- Name: TABLE log_errores; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.log_errores IS 'Registra errores ocurridos en funciones y triggers.';


--
-- Name: log_errores_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.log_errores_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.log_errores_id_seq OWNER TO postgres;

--
-- Name: log_errores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.log_errores_id_seq OWNED BY public.log_errores.id;


--
-- Name: productos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.productos (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    precio numeric(10,2) NOT NULL,
    stock integer NOT NULL,
    categoria_id integer,
    activo boolean DEFAULT true,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_stock_no_negativo CHECK ((stock >= 0)),
    CONSTRAINT productos_precio_check CHECK ((precio > (0)::numeric)),
    CONSTRAINT productos_stock_check CHECK ((stock >= 0))
);


ALTER TABLE public.productos OWNER TO postgres;

--
-- Name: TABLE productos; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.productos IS 'Almacena la información de los productos.';


--
-- Name: productos_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.productos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.productos_id_seq OWNER TO postgres;

--
-- Name: productos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.productos_id_seq OWNED BY public.productos.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roles (
    id integer NOT NULL,
    nombre character varying(50) NOT NULL
);


ALTER TABLE public.roles OWNER TO postgres;

--
-- Name: TABLE roles; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.roles IS 'Almacena los roles de los usuarios (admin, vendedor, etc.).';


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roles_id_seq OWNER TO postgres;

--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usuarios (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    password_cifrado bytea NOT NULL,
    rol_id integer,
    intentos_fallidos integer DEFAULT 0,
    bloqueado boolean DEFAULT false,
    fecha_desbloqueo timestamp without time zone,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fecha_expiracion date,
    sesion_activa boolean DEFAULT false,
    CONSTRAINT usuarios_email_check CHECK (((email)::text ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'::text)),
    CONSTRAINT usuarios_fecha_expiracion_check CHECK ((fecha_expiracion > CURRENT_DATE)),
    CONSTRAINT usuarios_intentos_fallidos_check CHECK ((intentos_fallidos >= 0))
);


ALTER TABLE public.usuarios OWNER TO postgres;

--
-- Name: TABLE usuarios; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.usuarios IS 'Almacena la información de los usuarios del sistema.';


--
-- Name: usuarios_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.usuarios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.usuarios_id_seq OWNER TO postgres;

--
-- Name: usuarios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.usuarios_id_seq OWNED BY public.usuarios.id;


--
-- Name: ventas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ventas (
    id integer NOT NULL,
    cliente_id integer,
    total numeric(10,2) NOT NULL,
    fecha_venta timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ventas_total_check CHECK ((total >= (0)::numeric))
);


ALTER TABLE public.ventas OWNER TO postgres;

--
-- Name: TABLE ventas; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.ventas IS 'Registra las ventas realizadas con su respectivo cliente y total.';


--
-- Name: ventas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ventas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ventas_id_seq OWNER TO postgres;

--
-- Name: ventas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ventas_id_seq OWNED BY public.ventas.id;


--
-- Name: auditoria_ventas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auditoria_ventas ALTER COLUMN id SET DEFAULT nextval('public.auditoria_ventas_id_seq'::regclass);


--
-- Name: categorias id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categorias ALTER COLUMN id SET DEFAULT nextval('public.categorias_id_seq'::regclass);


--
-- Name: clientes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes ALTER COLUMN id SET DEFAULT nextval('public.clientes_id_seq'::regclass);


--
-- Name: detalle_ventas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_ventas ALTER COLUMN id SET DEFAULT nextval('public.detalle_ventas_id_seq'::regclass);


--
-- Name: historial_stock id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historial_stock ALTER COLUMN id SET DEFAULT nextval('public.historial_stock_id_seq'::regclass);


--
-- Name: log_errores id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log_errores ALTER COLUMN id SET DEFAULT nextval('public.log_errores_id_seq'::regclass);


--
-- Name: productos id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.productos ALTER COLUMN id SET DEFAULT nextval('public.productos_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: usuarios id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios ALTER COLUMN id SET DEFAULT nextval('public.usuarios_id_seq'::regclass);


--
-- Name: ventas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ventas ALTER COLUMN id SET DEFAULT nextval('public.ventas_id_seq'::regclass);


--
-- Data for Name: auditoria_ventas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auditoria_ventas (id, usuario_id, venta_id, accion, fecha, estado_anterior, estado_nuevo) FROM stdin;
\.


--
-- Data for Name: categorias; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categorias (id, nombre, descripcion) FROM stdin;
\.


--
-- Data for Name: clientes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clientes (id, nombre, email, telefono, direccion) FROM stdin;
\.


--
-- Data for Name: detalle_ventas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.detalle_ventas (id, venta_id, producto_id, cantidad, precio_unitario) FROM stdin;
\.


--
-- Data for Name: historial_stock; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.historial_stock (id, producto_id, usuario_id, cantidad, tipo_movimiento, fecha) FROM stdin;
\.


--
-- Data for Name: log_errores; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.log_errores (id, usuario_id, error_mensaje, fecha) FROM stdin;
\.


--
-- Data for Name: productos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.productos (id, nombre, precio, stock, categoria_id, activo, fecha_creacion, fecha_modificacion) FROM stdin;
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roles (id, nombre) FROM stdin;
\.


--
-- Data for Name: usuarios; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.usuarios (id, nombre, email, password_cifrado, rol_id, intentos_fallidos, bloqueado, fecha_desbloqueo, fecha_creacion, fecha_modificacion, fecha_expiracion, sesion_activa) FROM stdin;
\.


--
-- Data for Name: ventas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ventas (id, cliente_id, total, fecha_venta) FROM stdin;
\.


--
-- Name: auditoria_ventas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auditoria_ventas_id_seq', 1, false);


--
-- Name: categorias_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categorias_id_seq', 1, false);


--
-- Name: clientes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.clientes_id_seq', 1, false);


--
-- Name: detalle_ventas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.detalle_ventas_id_seq', 1, false);


--
-- Name: historial_stock_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.historial_stock_id_seq', 1, false);


--
-- Name: log_errores_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.log_errores_id_seq', 1, false);


--
-- Name: productos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.productos_id_seq', 1, false);


--
-- Name: roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.roles_id_seq', 1, false);


--
-- Name: usuarios_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.usuarios_id_seq', 1, false);


--
-- Name: ventas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ventas_id_seq', 1, false);


--
-- Name: auditoria_ventas auditoria_ventas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auditoria_ventas
    ADD CONSTRAINT auditoria_ventas_pkey PRIMARY KEY (id);


--
-- Name: categorias categorias_nombre_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categorias
    ADD CONSTRAINT categorias_nombre_key UNIQUE (nombre);


--
-- Name: categorias categorias_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categorias
    ADD CONSTRAINT categorias_pkey PRIMARY KEY (id);


--
-- Name: clientes clientes_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_email_key UNIQUE (email);


--
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (id);


--
-- Name: detalle_ventas detalle_ventas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_ventas
    ADD CONSTRAINT detalle_ventas_pkey PRIMARY KEY (id);


--
-- Name: historial_stock historial_stock_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historial_stock
    ADD CONSTRAINT historial_stock_pkey PRIMARY KEY (id);


--
-- Name: log_errores log_errores_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log_errores
    ADD CONSTRAINT log_errores_pkey PRIMARY KEY (id);


--
-- Name: productos productos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_pkey PRIMARY KEY (id);


--
-- Name: roles roles_nombre_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_nombre_key UNIQUE (nombre);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: usuarios usuarios_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_email_key UNIQUE (email);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: ventas ventas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT ventas_pkey PRIMARY KEY (id);


--
-- Name: idx_clientes_nombre; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_clientes_nombre ON public.clientes USING btree (nombre text_pattern_ops);


--
-- Name: idx_detalle_ventas_venta_producto; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_detalle_ventas_venta_producto ON public.detalle_ventas USING btree (venta_id, producto_id);


--
-- Name: idx_historial_stock_producto; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_historial_stock_producto ON public.historial_stock USING btree (producto_id);


--
-- Name: idx_productos_categoria; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_productos_categoria ON public.productos USING btree (categoria_id);


--
-- Name: idx_productos_nombre; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_productos_nombre ON public.productos USING btree (nombre text_pattern_ops);


--
-- Name: idx_usuarios_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_usuarios_email ON public.usuarios USING btree (email);


--
-- Name: idx_usuarios_nombre; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usuarios_nombre ON public.usuarios USING btree (nombre text_pattern_ops);


--
-- Name: idx_ventas_cliente_fecha; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ventas_cliente_fecha ON public.ventas USING btree (cliente_id, fecha_venta);


--
-- Name: ventas trg_auditoria_ventas; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditoria_ventas AFTER INSERT OR DELETE OR UPDATE ON public.ventas FOR EACH ROW EXECUTE FUNCTION public.registrar_auditoria_ventas();


--
-- Name: auditoria_ventas auditoria_ventas_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auditoria_ventas
    ADD CONSTRAINT auditoria_ventas_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: auditoria_ventas auditoria_ventas_venta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auditoria_ventas
    ADD CONSTRAINT auditoria_ventas_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES public.ventas(id) ON DELETE CASCADE;


--
-- Name: detalle_ventas detalle_ventas_producto_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_ventas
    ADD CONSTRAINT detalle_ventas_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.productos(id) ON DELETE CASCADE;


--
-- Name: detalle_ventas detalle_ventas_venta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_ventas
    ADD CONSTRAINT detalle_ventas_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES public.ventas(id) ON DELETE CASCADE;


--
-- Name: historial_stock historial_stock_producto_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historial_stock
    ADD CONSTRAINT historial_stock_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.productos(id) ON DELETE CASCADE;


--
-- Name: historial_stock historial_stock_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historial_stock
    ADD CONSTRAINT historial_stock_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: log_errores log_errores_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log_errores
    ADD CONSTRAINT log_errores_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: productos productos_categoria_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES public.categorias(id) ON DELETE RESTRICT;


--
-- Name: usuarios usuarios_rol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_rol_id_fkey FOREIGN KEY (rol_id) REFERENCES public.roles(id) ON DELETE SET NULL;


--
-- Name: ventas ventas_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT ventas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

