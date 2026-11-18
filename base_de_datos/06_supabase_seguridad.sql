-- =====================================================================
--  ANIS · LA CASA DE LA HUMINTA
--  Script 06 · Seguridad para Supabase (Row Level Security)
-- ---------------------------------------------------------------------
--  SOLO PARA SUPABASE (usa auth.uid() y auth.jwt()).
--  Solo los usuarios registrados en la tabla "usuario" (la administradora)
--  pueden leer o escribir datos desde la aplicación. El rol anónimo no
--  tiene acceso.
--  Antes: crear en Supabase > Authentication el usuario con el MISMO email
--  que figura en la tabla usuario (o actualizar ese email):
--    UPDATE usuario SET email = 'correo.real@ejemplo.com' WHERE id_usuario = 1;
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_es_usuario_del_sistema()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM usuario u
    WHERE u.activo
      AND (u.auth_uid = auth.uid() OR lower(u.email) = lower(auth.jwt() ->> 'email'))
  )
$$;

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'usuario','categoria_producto','producto','unidad_medida','categoria_insumo','insumo','receta',
    'proveedor','proveedor_insumo','compra','lote','cliente','metodo_pago','venta','detalle_venta',
    'produccion','merma','movimiento_inventario','historial_precio','cierre_caja']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS acceso_usuario_sistema ON %I', t);
    EXECUTE format('CREATE POLICY acceso_usuario_sistema ON %I FOR ALL TO authenticated '
                   'USING (fn_es_usuario_del_sistema()) WITH CHECK (fn_es_usuario_del_sistema())', t);
  END LOOP;
END $$;

-- Vincula automáticamente el usuario de Supabase Auth en su primer ingreso
UPDATE usuario u SET auth_uid = a.id
FROM auth.users a
WHERE lower(a.email) = lower(u.email) AND u.auth_uid IS NULL;

-- Permisos: nada para anónimos; todo para usuarios autenticados (filtrado por RLS)
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
REVOKE EXECUTE ON ALL FUNCTIONS  IN SCHEMA public FROM anon, PUBLIC;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA public FROM anon, PUBLIC;
GRANT  SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT  USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT  EXECUTE ON ALL FUNCTIONS  IN SCHEMA public TO authenticated;
GRANT  EXECUTE ON ALL PROCEDURES IN SCHEMA public TO authenticated;
