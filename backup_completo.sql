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
-- Name: actualizar_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.actualizar_stock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    stock_actual INTEGER;
BEGIN
    -- Bloqueo para evitar problemas de concurrencia
    LOCK TABLE productos IN ROW EXCLUSIVE MODE;

    -- Obtener stock actual de forma segura
    SELECT stock INTO stock_actual
    FROM productos
    WHERE id = COALESCE(NEW.producto_id, OLD.producto_id);

    IF TG_OP = 'INSERT' THEN
        IF stock_actual < NEW.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para el producto % (Stock actual: %, cantidad requerida: %)', 
                NEW.producto_id, stock_actual, NEW.cantidad;
        END IF;
        UPDATE productos
        SET stock = stock_actual - NEW.cantidad
        WHERE id = NEW.producto_id;

        -- Insertar en historial_inventario
        INSERT INTO historial_inventario (producto_id, cantidad_anterior, cantidad_nueva, accion, fecha, usuario_id)
        VALUES (
            NEW.producto_id,
            stock_actual,
            stock_actual - NEW.cantidad,
            'Venta realizada',
            NOW(),
            COALESCE(NEW.usuario_creacion, NEW.usuario_modificacion, 1) -- Valor por defecto si no hay usuario
        );

    ELSIF TG_OP = 'DELETE' THEN
        UPDATE productos
        SET stock = stock_actual + OLD.cantidad
        WHERE id = OLD.producto_id;

    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.producto_id <> OLD.producto_id THEN
            RAISE EXCEPTION 'No se puede cambiar el producto en una venta existente';
        END IF;
        UPDATE productos
        SET stock = stock_actual + OLD.cantidad - NEW.cantidad
        WHERE id = NEW.producto_id;
    END IF;

    -- Asegúrate de que esta línea esté al final
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.actualizar_stock() OWNER TO postgres;

--
-- Name: actualizar_total_venta(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.actualizar_total_venta() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE ventas
    SET total = COALESCE((SELECT SUM(subtotal) FROM detalle_ventas WHERE venta_id = NEW.venta_id), 0)
    WHERE id = NEW.venta_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.actualizar_total_venta() OWNER TO postgres;

--
-- Name: calcular_subtotal(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calcular_subtotal() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.subtotal := NEW.cantidad * NEW.precio_unitario;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.calcular_subtotal() OWNER TO postgres;

--
-- Name: gestionar_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.gestionar_stock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    stock_actual INTEGER;
BEGIN
    -- Bloqueo para evitar problemas de concurrencia
    SELECT stock INTO stock_actual 
    FROM productos 
    WHERE id = COALESCE(NEW.producto_id, OLD.producto_id)
    FOR UPDATE;

    -- Manejo de inserción
    IF TG_OP = 'INSERT' THEN
        IF stock_actual < NEW.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para el producto % (Stock actual: %, cantidad requerida: %)', 
                NEW.producto_id, stock_actual, NEW.cantidad;
        END IF;
        UPDATE productos 
        SET stock = stock_actual - NEW.cantidad 
        WHERE id = NEW.producto_id;

    -- Manejo de eliminación
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE productos 
        SET stock = stock_actual + OLD.cantidad 
        WHERE id = OLD.producto_id;

    -- Manejo de actualización
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.producto_id <> OLD.producto_id THEN
            RAISE EXCEPTION 'No se puede cambiar el producto en una venta existente';
        END IF;
        UPDATE productos 
        SET stock = stock_actual + OLD.cantidad - NEW.cantidad 
        WHERE id = NEW.producto_id;
    END IF;

    -- Insertar registro en historial_inventario
    INSERT INTO historial_inventario (producto_id, cantidad_anterior, cantidad_nueva, accion, fecha, usuario_id)
    VALUES (
        COALESCE(NEW.producto_id, OLD.producto_id),  -- Producto afectado
        stock_actual,  -- Stock antes de la operación
        CASE TG_OP
            WHEN 'INSERT' THEN stock_actual - NEW.cantidad
            WHEN 'DELETE' THEN stock_actual + OLD.cantidad
            WHEN 'UPDATE' THEN stock_actual + OLD.cantidad - NEW.cantidad
        END,  -- Stock después de la operación
        CASE TG_OP
            WHEN 'INSERT' THEN 'Venta realizada'
            WHEN 'DELETE' THEN 'Venta eliminada'
            WHEN 'UPDATE' THEN 'Venta modificada'
        END,  -- Tipo de acción
        NOW(),  -- Fecha y hora de la operación
        COALESCE(NEW.usuario_creacion, NEW.usuario_modificacion, OLD.usuario_creacion, OLD.usuario_modificacion, 1)  -- Usuario responsable
    );

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.gestionar_stock() OWNER TO postgres;

--
-- Name: reabastecer_producto(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.reabastecer_producto() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.stock < 10 THEN  -- Stock mínimo definido
        NEW.stock = NEW.stock + 50;  -- Cantidad fija de reabastecimiento
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.reabastecer_producto() OWNER TO postgres;

--
-- Name: registrar_auditoria_ventas(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.registrar_auditoria_ventas() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_usuario INTEGER;
BEGIN
    -- Intentamos obtener el ID del usuario actual, si existe
    BEGIN
        v_usuario := current_setting('app.current_user_id', true)::INTEGER;
    EXCEPTION
        WHEN others THEN
            v_usuario := NULL;  -- Si no se puede obtener, lo dejamos como NULL
    END;

    -- Verificamos si ya existe un registro en la auditoría para esta venta
    IF NOT EXISTS (SELECT 1 FROM public.auditoria_ventas WHERE venta_id = NEW.id AND accion = 'Actualización' AND detalle = 'Cambio en venta') THEN
        -- Si no existe, insertamos el registro
        INSERT INTO public.auditoria_ventas (venta_id, accion, detalle, usuario_id)
        VALUES (NEW.id, 'Actualización', 'Cambio en venta', v_usuario);
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.registrar_auditoria_ventas() OWNER TO postgres;

--
-- Name: registrar_entrada_inventario(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.registrar_entrada_inventario() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO historial_inventario (producto_id, cantidad_anterior, cantidad_nueva, accion, fecha)
    VALUES (NEW.id, OLD.stock, NEW.stock, 'Ajuste', CURRENT_TIMESTAMP); 
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.registrar_entrada_inventario() OWNER TO postgres;

--
-- Name: validar_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validar_stock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    stock_actual INTEGER;
BEGIN
    -- Obtener el stock actual del producto
    SELECT stock INTO stock_actual FROM productos WHERE id = NEW.producto_id;
    
    -- Verificar si hay suficiente stock
    IF stock_actual < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para el producto %', NEW.producto_id;
    END IF;
    
    -- Actualizar el stock
    UPDATE productos 
    SET stock = stock - NEW.cantidad
    WHERE id = NEW.producto_id;

    -- Registrar en historial de inventario
    INSERT INTO historial_inventario (producto_id, cantidad_anterior, cantidad_nueva, accion)
    VALUES (NEW.producto_id, stock_actual, stock_actual - NEW.cantidad, 'Venta realizada');

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validar_stock() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auditoria_ventas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auditoria_ventas (
    id integer NOT NULL,
    venta_id integer NOT NULL,
    accion text NOT NULL,
    detalle text,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usuario_id integer NOT NULL
);


ALTER TABLE public.auditoria_ventas OWNER TO postgres;

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
    nombre character varying(100) NOT NULL
);


ALTER TABLE public.categorias OWNER TO postgres;

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
    email character varying(100) NOT NULL,
    telefono character varying(20),
    direccion text,
    fecha_creacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    usuario_creacion integer NOT NULL,
    usuario_modificacion integer NOT NULL
);


ALTER TABLE public.clientes OWNER TO postgres;

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
    venta_id integer NOT NULL,
    producto_id integer NOT NULL,
    cantidad integer NOT NULL,
    precio_unitario numeric(10,2) NOT NULL,
    subtotal numeric(10,2) GENERATED ALWAYS AS (((cantidad)::numeric * precio_unitario)) STORED,
    fecha_creacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    usuario_creacion integer,
    usuario_modificacion integer,
    CONSTRAINT detalle_ventas_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT detalle_ventas_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric))
);


ALTER TABLE public.detalle_ventas OWNER TO postgres;

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
-- Name: historial_inventario; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.historial_inventario (
    id integer NOT NULL,
    producto_id integer NOT NULL,
    cantidad_anterior integer NOT NULL,
    cantidad_nueva integer NOT NULL,
    accion text NOT NULL,
    fecha timestamp without time zone DEFAULT now() NOT NULL,
    usuario_id integer NOT NULL,
    motivo text,
    CONSTRAINT check_accion CHECK ((accion = ANY (ARRAY['Venta realizada'::text, 'Venta eliminada'::text, 'Venta modificada'::text, 'Compra'::text, 'Ajuste'::text])))
);


ALTER TABLE public.historial_inventario OWNER TO postgres;

--
-- Name: historial_inventario_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.historial_inventario_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.historial_inventario_id_seq OWNER TO postgres;

--
-- Name: historial_inventario_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.historial_inventario_id_seq OWNED BY public.historial_inventario.id;


--
-- Name: log_errores; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.log_errores (
    id integer NOT NULL,
    fecha timestamp without time zone DEFAULT now(),
    funcion text NOT NULL,
    mensaje text NOT NULL
);


ALTER TABLE public.log_errores OWNER TO postgres;

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
    categoria_id integer NOT NULL,
    activo boolean DEFAULT true,
    fecha_creacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    usuario_creacion integer NOT NULL,
    usuario_modificacion integer NOT NULL,
    CONSTRAINT check_stock_non_negative CHECK ((stock >= 0)),
    CONSTRAINT chk_precio_positive CHECK ((precio > (0)::numeric)),
    CONSTRAINT chk_stock_positive CHECK ((stock >= 0)),
    CONSTRAINT productos_precio_check CHECK ((precio >= (0)::numeric))
);


ALTER TABLE public.productos OWNER TO postgres;

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
-- Name: usuarios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usuarios (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    "contraseña" character varying(100) NOT NULL,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.usuarios OWNER TO postgres;

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
    cliente_id integer NOT NULL,
    fecha timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    total numeric(10,2) DEFAULT 0 NOT NULL,
    descuento numeric(10,2) DEFAULT 0,
    fecha_creacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    usuario_creacion integer NOT NULL,
    usuario_modificacion integer NOT NULL,
    CONSTRAINT chk_ventas_total_positive CHECK ((total >= (0)::numeric))
);


ALTER TABLE public.ventas OWNER TO postgres;

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
-- Name: vista_ventas_detalladas; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_ventas_detalladas AS
 SELECT v.id AS venta_id,
    c.nombre AS cliente,
    p.nombre AS producto,
    dv.cantidad,
    dv.precio_unitario,
    dv.subtotal
   FROM (((public.ventas v
     JOIN public.clientes c ON ((v.cliente_id = c.id)))
     JOIN public.detalle_ventas dv ON ((v.id = dv.venta_id)))
     JOIN public.productos p ON ((dv.producto_id = p.id)));


ALTER VIEW public.vista_ventas_detalladas OWNER TO postgres;

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
-- Name: historial_inventario id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historial_inventario ALTER COLUMN id SET DEFAULT nextval('public.historial_inventario_id_seq'::regclass);


--
-- Name: log_errores id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log_errores ALTER COLUMN id SET DEFAULT nextval('public.log_errores_id_seq'::regclass);


--
-- Name: productos id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.productos ALTER COLUMN id SET DEFAULT nextval('public.productos_id_seq'::regclass);


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

COPY public.auditoria_ventas (id, venta_id, accion, detalle, fecha, usuario_id) FROM stdin;
4	2	Actualización	Cambio en venta	2025-02-28 22:04:01.698631	1
5	6	Actualización	Cambio en venta	2025-02-28 22:07:42.528831	1
6	7	Actualización	Cambio en venta	2025-02-28 22:25:25.693715	1
7	8	Actualización	Cambio en venta	2025-03-01 10:08:01.760138	1
8	5	Actualización	Cambio en venta	2025-03-01 10:56:53.13366	1
9	3	Actualización	Cambio en venta	2025-03-01 11:03:41.888213	1
10	4	Actualización	Cambio en venta	2025-03-01 11:03:41.888213	1
11	1	Actualización	Cambio en venta	2025-03-01 18:09:50.918301	1
\.


--
-- Data for Name: categorias; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categorias (id, nombre) FROM stdin;
1	Electrónica
2	Electrónica
\.


--
-- Data for Name: clientes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clientes (id, nombre, email, telefono, direccion, fecha_creacion, fecha_modificacion, usuario_creacion, usuario_modificacion) FROM stdin;
2	Carlos López	carlos@example.com	\N	\N	2025-02-28 21:21:15.560589-05	2025-02-28 21:21:15.560589-05	1	1
4	Juan Pérez	juan2@example.com	\N	\N	2025-02-28 21:27:30.528612-05	2025-02-28 21:27:30.528612-05	1	1
5	Ana García	ana@example.com	\N	\N	2025-02-28 22:07:27.754572-05	2025-02-28 22:07:27.754572-05	1	1
6	Pedro Martínez	pedro.martinez@example.com	\N	\N	2025-03-01 10:19:19.440218-05	2025-03-01 10:19:19.440218-05	1	1
1	Pedro Martínez Actualizado	pedro.martinez.new@example.com	\N	\N	2025-02-28 19:07:04.261959-05	2025-02-28 19:07:04.261959-05	1	1
7	Cliente Anónimo	anonimo@example.com	\N	\N	2025-03-01 10:56:53.130264-05	2025-03-01 10:56:53.130264-05	1	1
\.


--
-- Data for Name: detalle_ventas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.detalle_ventas (id, venta_id, producto_id, cantidad, precio_unitario, fecha_creacion, fecha_modificacion, usuario_creacion, usuario_modificacion) FROM stdin;
3	1	2	2	1000.00	2025-02-28 21:21:15.564573-05	2025-02-28 21:21:15.564573-05	\N	\N
4	1	2	2	1000.00	2025-02-28 21:29:36.683739-05	2025-02-28 21:29:36.683739-05	\N	\N
5	2	2	3	1000.00	2025-02-28 21:39:38.636697-05	2025-02-28 21:39:38.636697-05	\N	\N
6	1	2	3	1000.00	2025-02-28 22:08:33.05225-05	2025-02-28 22:08:33.05225-05	\N	\N
7	7	2	3	1000.00	2025-03-01 10:08:13.489976-05	2025-03-01 10:08:13.489976-05	\N	\N
8	8	2	3	1000.00	2025-03-01 10:15:34.179579-05	2025-03-01 10:15:34.179579-05	\N	\N
9	4	2	3	1000.00	2025-03-01 11:06:09.790163-05	2025-03-01 11:06:09.790163-05	\N	\N
10	1	2	3	100.00	2025-03-01 18:07:56.762155-05	2025-03-01 18:07:56.762155-05	\N	\N
11	1	3	2	500.00	2025-03-01 18:11:34.982404-05	2025-03-01 18:11:34.982404-05	\N	\N
\.


--
-- Data for Name: historial_inventario; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.historial_inventario (id, producto_id, cantidad_anterior, cantidad_nueva, accion, fecha, usuario_id, motivo) FROM stdin;
5	2	50	150	Ajuste	2025-02-28 21:19:25.795207	1	\N
6	2	150	148	Venta realizada	2025-02-28 21:21:15.564573	1	\N
7	2	146	144	Venta realizada	2025-02-28 21:21:15.564573	1	\N
8	2	142	140	Venta realizada	2025-02-28 21:21:15.564573	1	\N
9	2	140	138	Venta realizada	2025-02-28 21:29:36.683739	1	\N
10	2	136	134	Venta realizada	2025-02-28 21:29:36.683739	1	\N
11	2	132	130	Venta realizada	2025-02-28 21:29:36.683739	1	\N
12	2	130	127	Venta realizada	2025-02-28 21:39:38.636697	1	\N
13	2	124	121	Venta realizada	2025-02-28 21:39:38.636697	1	\N
14	2	118	115	Venta realizada	2025-02-28 21:39:38.636697	1	\N
15	2	115	112	Venta realizada	2025-02-28 22:08:33.05225	1	\N
16	2	109	106	Venta realizada	2025-02-28 22:08:33.05225	1	\N
17	2	103	100	Venta realizada	2025-02-28 22:08:33.05225	1	\N
18	2	100	97	Venta realizada	2025-03-01 10:08:13.489976	1	\N
19	2	94	91	Venta realizada	2025-03-01 10:08:13.489976	1	\N
20	2	88	85	Venta realizada	2025-03-01 10:08:13.489976	1	\N
21	2	85	82	Venta realizada	2025-03-01 10:15:34.179579	1	\N
22	2	79	76	Venta realizada	2025-03-01 10:15:34.179579	1	\N
23	2	73	70	Venta realizada	2025-03-01 10:15:34.179579	1	\N
24	2	70	67	Venta realizada	2025-03-01 11:06:09.790163	1	\N
25	2	64	61	Venta realizada	2025-03-01 11:06:09.790163	1	\N
26	2	58	55	Venta realizada	2025-03-01 11:06:09.790163	1	\N
27	2	55	52	Venta realizada	2025-03-01 18:07:56.762155	1	\N
28	2	49	46	Venta realizada	2025-03-01 18:07:56.762155	1	\N
29	2	43	40	Venta realizada	2025-03-01 18:07:56.762155	1	\N
30	3	50	48	Venta realizada	2025-03-01 18:11:34.982404	1	\N
31	3	46	44	Venta realizada	2025-03-01 18:11:34.982404	1	\N
32	3	42	40	Venta realizada	2025-03-01 18:11:34.982404	1	\N
\.


--
-- Data for Name: log_errores; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.log_errores (id, fecha, funcion, mensaje) FROM stdin;
\.


--
-- Data for Name: productos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.productos (id, nombre, precio, stock, categoria_id, activo, fecha_creacion, fecha_modificacion, usuario_creacion, usuario_modificacion) FROM stdin;
1	Smartphone	500.00	100	1	t	2025-02-28 19:06:57.484139-05	2025-02-28 19:06:57.484139-05	1	1
2	Producto de prueba	100.00	40	1	t	2025-02-28 21:15:26.236276-05	2025-02-28 21:15:26.236276-05	1	1
3	Laptop	1000.00	40	1	t	2025-02-28 21:21:15.558248-05	2025-02-28 21:21:15.558248-05	1	1
\.


--
-- Data for Name: usuarios; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.usuarios (id, nombre, email, "contraseña", fecha_creacion) FROM stdin;
1	Usuario Desconocido	desconocido@example.com	password_encriptado	2025-03-01 18:38:12.045966
\.


--
-- Data for Name: ventas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ventas (id, cliente_id, fecha, total, descuento, fecha_creacion, fecha_modificacion, usuario_creacion, usuario_modificacion) FROM stdin;
2	7	2025-02-28 21:21:15.563-05	3000.00	5.00	2025-02-28 21:21:15.563-05	2025-02-28 21:21:15.563-05	1	1
7	7	2025-02-28 22:25:25.693715-05	3000.00	5.00	2025-02-28 22:25:25.693715-05	2025-02-28 22:25:25.693715-05	1	1
8	7	2025-03-01 10:08:01.760138-05	3000.00	5.00	2025-03-01 10:08:01.760138-05	2025-03-01 10:08:01.760138-05	1	1
3	4	2025-02-28 21:28:39.918682-05	0.00	10.00	2025-02-28 21:28:39.918682-05	2025-02-28 21:28:39.918682-05	1	1
6	5	2025-02-28 22:07:42.528831-05	0.00	10.00	2025-02-28 22:07:42.528831-05	2025-02-28 22:07:42.528831-05	1	1
5	7	2025-02-28 21:35:51.414433-05	0.00	5.00	2025-02-28 21:35:51.414433-05	2025-02-28 21:35:51.414433-05	1	1
4	4	2025-02-28 21:29:32.049539-05	3000.00	10.00	2025-02-28 21:29:32.049539-05	2025-02-28 21:29:32.049539-05	1	1
1	1	2025-03-01 18:09:50.918301-05	8300.00	0.00	2025-03-01 18:09:50.918301-05	2025-03-01 18:09:50.918301-05	1	1
\.


--
-- Name: auditoria_ventas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auditoria_ventas_id_seq', 11, true);


--
-- Name: categorias_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categorias_id_seq', 2, true);


--
-- Name: clientes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.clientes_id_seq', 8, true);


--
-- Name: detalle_ventas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.detalle_ventas_id_seq', 13, true);


--
-- Name: historial_inventario_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.historial_inventario_id_seq', 42, true);


--
-- Name: log_errores_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.log_errores_id_seq', 1, false);


--
-- Name: productos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.productos_id_seq', 3, true);


--
-- Name: usuarios_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.usuarios_id_seq', 1, false);


--
-- Name: ventas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ventas_id_seq', 8, true);


--
-- Name: auditoria_ventas auditoria_ventas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auditoria_ventas
    ADD CONSTRAINT auditoria_ventas_pkey PRIMARY KEY (id);


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
-- Name: historial_inventario historial_inventario_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historial_inventario
    ADD CONSTRAINT historial_inventario_pkey PRIMARY KEY (id);


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
-- Name: idx_clientes_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_clientes_email ON public.clientes USING btree (email);


--
-- Name: idx_detalle_ventas_producto; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_detalle_ventas_producto ON public.detalle_ventas USING btree (producto_id);


--
-- Name: idx_detalle_ventas_venta; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_detalle_ventas_venta ON public.detalle_ventas USING btree (venta_id);


--
-- Name: idx_historial_fecha; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_historial_fecha ON public.historial_inventario USING btree (fecha);


--
-- Name: idx_historial_inventario_producto; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_historial_inventario_producto ON public.historial_inventario USING btree (producto_id);


--
-- Name: idx_productos_categoria_stock; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_productos_categoria_stock ON public.productos USING btree (categoria_id, stock);


--
-- Name: idx_productos_nombre; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_productos_nombre ON public.productos USING btree (nombre);


--
-- Name: idx_ventas_cliente; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ventas_cliente ON public.ventas USING btree (cliente_id);


--
-- Name: idx_ventas_fecha; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ventas_fecha ON public.ventas USING btree (fecha);


--
-- Name: idx_ventas_fecha_cliente; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ventas_fecha_cliente ON public.ventas USING btree (fecha, cliente_id);


--
-- Name: detalle_ventas trg_actualizar_stock; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_actualizar_stock AFTER INSERT OR DELETE OR UPDATE ON public.detalle_ventas FOR EACH ROW EXECUTE FUNCTION public.actualizar_stock();


--
-- Name: detalle_ventas trg_actualizar_total_venta; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_actualizar_total_venta AFTER INSERT OR DELETE OR UPDATE ON public.detalle_ventas FOR EACH ROW EXECUTE FUNCTION public.actualizar_total_venta();


--
-- Name: ventas trg_auditoria_ventas; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditoria_ventas AFTER DELETE OR UPDATE ON public.ventas FOR EACH ROW EXECUTE FUNCTION public.registrar_auditoria_ventas();


--
-- Name: detalle_ventas trg_calcular_subtotal; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_calcular_subtotal BEFORE INSERT OR UPDATE ON public.detalle_ventas FOR EACH ROW EXECUTE FUNCTION public.calcular_subtotal();


--
-- Name: ventas trigger_auditoria_ventas; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_auditoria_ventas AFTER INSERT OR DELETE OR UPDATE ON public.ventas FOR EACH ROW EXECUTE FUNCTION public.registrar_auditoria_ventas();


--
-- Name: ventas trigger_gestionar_stock; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_gestionar_stock AFTER INSERT OR DELETE OR UPDATE ON public.ventas FOR EACH ROW EXECUTE FUNCTION public.gestionar_stock();


--
-- Name: productos trigger_reabastecer; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_reabastecer BEFORE UPDATE ON public.productos FOR EACH ROW EXECUTE FUNCTION public.reabastecer_producto();


--
-- Name: productos trigger_registrar_entrada; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_registrar_entrada BEFORE UPDATE ON public.productos FOR EACH ROW WHEN (((new.stock IS DISTINCT FROM old.stock) AND (new.stock > old.stock))) EXECUTE FUNCTION public.registrar_entrada_inventario();


--
-- Name: detalle_ventas trigger_validar_stock; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_validar_stock BEFORE INSERT ON public.detalle_ventas FOR EACH ROW EXECUTE FUNCTION public.validar_stock();


--
-- Name: clientes fk_clientes_usuario_creacion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT fk_clientes_usuario_creacion FOREIGN KEY (usuario_creacion) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: detalle_ventas fk_detalle_ventas_producto; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_ventas
    ADD CONSTRAINT fk_detalle_ventas_producto FOREIGN KEY (producto_id) REFERENCES public.productos(id);


--
-- Name: detalle_ventas fk_detalle_ventas_venta; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_ventas
    ADD CONSTRAINT fk_detalle_ventas_venta FOREIGN KEY (venta_id) REFERENCES public.ventas(id);


--
-- Name: historial_inventario fk_historial_producto; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historial_inventario
    ADD CONSTRAINT fk_historial_producto FOREIGN KEY (producto_id) REFERENCES public.productos(id);


--
-- Name: productos fk_productos_categoria; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT fk_productos_categoria FOREIGN KEY (categoria_id) REFERENCES public.categorias(id) ON DELETE SET NULL;


--
-- Name: ventas fk_ventas_cliente; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT fk_ventas_cliente FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE SET NULL;


--
-- Name: ventas fk_ventas_usuario_creacion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT fk_ventas_usuario_creacion FOREIGN KEY (usuario_creacion) REFERENCES public.usuarios(id);


--
-- PostgreSQL database dump complete
--

